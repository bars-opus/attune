-- Spec 2 W7c (§4.3, §4.8, §4.9 W7c, §6.3, §6.5, §6.6, §7.1; R-60, R-65,
-- R-67): escalations, the law-enforcement request log, the transparency
-- summary, the CSAM hold lift.
--   * dating_escalations: what a person did (police, NCMEC, IWF, Ghana's
--     CSA, CSA 292 with the victim's consent), never an automatic send:
--     nothing here, and nothing reading this table, makes a call.
--   * law_enforcement_requests: every request and its decision, recorded
--     and read by the safety owner only (R-60).
--   * The transparency summary (§6.6): requests by country and decision,
--     how many were met, reports by category, actions taken, appeals and
--     how many were overturned; counts only; the safety owner only.
--   * The CSAM hold lift (owner 2026-11-22): the safety owner only, after
--     review, with a written reason, audited once; Spec 1's account hold
--     is untouched.
--   * The purge: moderation actions, escalations and the request log at 2
--     years (§4.8); a case (and with it its reports, audit rows and
--     escalations) stays while a live restriction or record from it lasts.
--   * Re-created from their live bodies: the purge's two functions, the
--     unavailable home state (a closer look never shows; a carried hold or
--     age check shows as itself), the card report (a P0 card goes whatever
--     the block did), the audit log (R-60) and the audit guard (R-67).
--   * Fix round 1: the log never drops a decision (every input checked,
--     a create replay only when every input matches, "exists" otherwise,
--     a disclosure never narrowed, the notice on its own); the summary by
--     country and type; a case's escalations for the console; a case still
--     open (or an appeal case whose restriction lives) keeps its rows; a
--     CSAM hit always writes its own hold (all three paths); a case lift
--     of a carried hold ends its record; a carried CSAM hold is not
--     appealable.
--   * W7 final server fix: one ID-check design (Ask for ID writes its own
--     age check with a reference code; every ID action keys on it being
--     live; the case and queue read id_check); a restriction is its
--     case's, in placement and in ending (an orphaned case's records end
--     with it; the carry takes the number's lock and relinks the case); a
--     closer look follows the number; the queue by kind; the W7 gate on
--     the flag; the SLA sentence only with named moderators; a refused
--     SLA alert counted; pre-W7 reports get their case.
-- Nothing here turns a flag on. Grants in
-- 20261121120010_dating_v2_escalations_grants.sql; this file revokes what
-- it creates from every API role first.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------------
-- 1. Escalations (§4.3, §6.5): a record of what a person did, never a
--    send. No trigger, no queue, no HTTP call reads this table; sextortion
--    to CSA 292 is recorded only with the victim's consent (its own kind).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dating_escalations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid REFERENCES public.dating_moderation_cases (id) ON DELETE SET NULL,
  kind text NOT NULL CHECK (kind IN ('police', 'ncmec', 'iwf', 'csa', 'csa_292_with_consent')),
  recorded_by uuid NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  reference text CHECK (reference IS NULL OR char_length(reference) BETWEEN 1 AND 200)
);
CREATE INDEX IF NOT EXISTS dating_escalations_case_idx ON public.dating_escalations (case_id);
ALTER TABLE public.dating_escalations ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
-- 2. The law-enforcement request log (§4.3, §6.6): every request and its
--    decision, by the safety owner.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.law_enforcement_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  received_at timestamptz NOT NULL,
  jurisdiction text NOT NULL CHECK (jurisdiction ~ '^[A-Z]{2}$'),
  legal_basis text NOT NULL CHECK (char_length(legal_basis) BETWEEN 1 AND 300),
  scope text NOT NULL CHECK (char_length(scope) BETWEEN 1 AND 500),
  emergency boolean NOT NULL DEFAULT false,
  target_user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  decision text NOT NULL DEFAULT 'pending'
    CHECK (decision IN ('pending', 'disclosed', 'partly_disclosed', 'refused', 'contested')),
  disclosed_categories text[] NOT NULL DEFAULT '{}'
    CHECK (disclosed_categories <@ ARRAY['account', 'profile', 'messages', 'reports', 'restrictions', 'verification']::text[]),
  user_notified_at timestamptz,
  decided_by uuid,
  decided_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((decision IN ('disclosed', 'partly_disclosed')) = (cardinality(disclosed_categories) > 0)),
  CHECK ((decision = 'pending') = (decided_at IS NULL))
);
CREATE INDEX IF NOT EXISTS law_enforcement_requests_received_idx ON public.law_enforcement_requests (received_at);
ALTER TABLE public.law_enforcement_requests ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
-- 2b. The audit (R-67, owner 2026-11-22): the CSAM hold lift is one of
--     its actions; a TRUNCATE is refused as an UPDATE or DELETE is (the
--     W7b guard; only a foreign key's own SET NULL and the 2-year purge
--     pass, see 4).
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_moderation_actions DROP CONSTRAINT IF EXISTS dating_moderation_actions_action_check;
ALTER TABLE public.dating_moderation_actions ADD CONSTRAINT dating_moderation_actions_action_check
  CHECK (action IN ('open_case', 'claim', 'dismiss', 'hold', 'lift_hold', 'restrict', 'ask_for_id', 'confirm_minor', 'note',
                    'decide_appeal', 'photo_decide', 'verification_decide', 'publish_country', 'opinions_view', 'opinions_remove',
                    'escalation', 'law_enforcement_request', 'lift_csam_hold', 'close_no_id')) NOT VALID;
ALTER TABLE public.dating_moderation_actions VALIDATE CONSTRAINT dating_moderation_actions_action_check; -- fix round 1 (M-13)
DROP TRIGGER IF EXISTS dating_moderation_actions_no_truncate ON public.dating_moderation_actions;
CREATE TRIGGER dating_moderation_actions_no_truncate
  BEFORE TRUNCATE ON public.dating_moderation_actions
  FOR EACH STATEMENT EXECUTE FUNCTION private.dating_moderation_actions_guard();

-- ---------------------------------------------------------------------
-- 2c. (Owner 2026-11-22) Awaiting ID: Ask for ID leaves its case open (in
--     review) and stamps when it asked; the console reads such a case as
--     'awaiting_id'. Every open-case rule (one open case per person, the
--     report's join, the generation exclusion, the clock, the purge's keep)
--     applies unchanged, because the case stays open.
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_moderation_cases ADD COLUMN IF NOT EXISTS awaiting_id_since timestamptz;
-- Fix round 5: the age check the ask placed, or the live one it reused (W4's
-- own, or a carried one), so Lift hold from awaiting lifts that one.
ALTER TABLE public.dating_moderation_cases ADD COLUMN IF NOT EXISTS awaiting_id_restriction uuid;
-- Fix round 5 (M-R4-3): the one test of "awaiting the ID", for every reader
-- and writer (pure).
CREATE OR REPLACE FUNCTION private.dating_case_awaiting_id(p_state text, p_since timestamptz)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(p_state = 'in_review' AND p_since IS NOT NULL, false);
$$;

-- ---------------------------------------------------------------------
-- 3. The console's escalation, the log and the transparency summary.
--    Every write follows W7b's rules (Task 5 fix round 1): not_moderator
--    counted, the person's setup lock before the case row, a party
--    refused, 2 s then busy (counted), a replay answered as the first
--    call was with no second row or audit row.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.moderation_record_escalation(p_actor uuid, p_case uuid, p_kind text, p_reference text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v_ref constant text := NULLIF(btrim(coalesce(p_reference, '')), '');
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 8: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF p_kind IS NULL OR p_kind NOT IN ('police', 'ncmec', 'iwf', 'csa', 'csa_292_with_consent')
     OR coalesce(char_length(v_ref), 0) > 200 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  BEGIN -- Task 8 (W7b rule): a lock not had in 2 s answers busy (counted)
    -- The person's setup lock, then the case row; a party is refused (counted).
    c := private.dating_case_lock(v_mod, p_case);
    IF c.id IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    -- Fix round 1 (M-5, §6.5): sextortion goes to CSA only as the
    -- victim's-consent kind, never as plain CSA.
    IF p_kind = 'csa' AND (c.signal_kind = 'chat_sextortion'
                           OR EXISTS (SELECT 1 FROM public.dating_reports AS r WHERE r.case_id = c.id AND r.category = 'sextortion')) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'consent_kind_required');
    END IF;
    -- The same record by the same moderator again is a replay.
    IF EXISTS (SELECT 1 FROM public.dating_escalations AS e
                WHERE e.case_id = c.id AND e.kind = p_kind AND e.recorded_by = p_actor AND e.reference IS NOT DISTINCT FROM v_ref) THEN
      RETURN pg_catalog.jsonb_build_object('ok', true);
    END IF;
    INSERT INTO public.dating_escalations (case_id, kind, recorded_by, reference) VALUES (c.id, p_kind, p_actor, v_ref);
    PERFORM private.dating_audit(p_actor, c.id, 'escalation', c.target_user_id, pg_catalog.jsonb_build_object('kind', p_kind));
    RETURN pg_catalog.jsonb_build_object('ok', true);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- A read that counts is a write (Task 5): VOLATILE.
CREATE OR REPLACE FUNCTION public.moderation_le_requests(p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 8: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'requests', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', r.id, 'received_at', r.received_at,
             'jurisdiction', r.jurisdiction, 'legal_basis', r.legal_basis, 'scope', r.scope, 'emergency', r.emergency,
             'decision', r.decision, 'disclosed_categories', to_jsonb(r.disclosed_categories),
             'user_notified_at', r.user_notified_at, 'decided_at', r.decided_at) ORDER BY r.received_at DESC)
      FROM public.law_enforcement_requests AS r), '[]'::jsonb));
END;
$$;

-- A request as received (pending), or its decision; the safety owner only.
-- Fix round 1 (I-1, M-2, M-3, M-4, M-7):
--   * every input is checked first (a decision that is not one, categories
--     that are not a list or don't fit the decision, a received time ahead
--     of now or past the log's 2 years: invalid);
--   * a create is a replay only when every input matches the row (its
--     decision, categories and notice too): it answers the first id. The
--     same request with another decision answers {ok: false, reason:
--     'exists', id}: the console decides it through p_request. One create
--     at a time per request (an advisory lock on its identity).
--   * a decision is never undone to pending; once something was disclosed
--     only a wider disclosure may follow (already_disclosed), so what was
--     disclosed stays recorded;
--   * the same decision again is a replay, or, with user_notified, stamps
--     the notice alone (the decision, its time and decider kept); a create
--     honours user_notified too.
CREATE OR REPLACE FUNCTION public.moderation_record_le_request(p_actor uuid, p_request uuid, p_values jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v_id uuid;
  v_decision text := coalesce(p_values ->> 'decision', 'pending');
  v_cats text[];
  v_notify boolean;
  v_at timestamptz;
  v_emergency boolean;
  v_target uuid;
  q public.law_enforcement_requests;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 8: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  IF p_values IS NULL OR jsonb_typeof(p_values) <> 'object' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF p_request IS NOT NULL AND v_decision = 'pending' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid'); -- Task 8: a decision is never undone
  END IF;
  BEGIN -- Task 8 (W7b rule): a lock not had in 2 s answers busy (counted)
  BEGIN
    IF v_decision NOT IN ('pending', 'disclosed', 'partly_disclosed', 'refused', 'contested')
       OR coalesce(jsonb_typeof(p_values -> 'disclosed_categories'), 'array') <> 'array' THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
    END IF;
    v_cats := ARRAY(SELECT DISTINCT x FROM jsonb_array_elements_text(coalesce(p_values -> 'disclosed_categories', '[]'::jsonb)) AS x
                     ORDER BY x);
    IF ((v_decision IN ('disclosed', 'partly_disclosed')) IS DISTINCT FROM (cardinality(v_cats) > 0))
       OR NOT coalesce(v_cats <@ ARRAY['account', 'profile', 'messages', 'reports', 'restrictions', 'verification']::text[], false) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
    END IF;
    v_notify := coalesce((p_values ->> 'user_notified')::boolean, false);
    IF p_request IS NULL THEN
      v_at := (p_values ->> 'received_at')::timestamptz;
      IF v_at IS NULL OR v_at > now() + interval '1 day' OR v_at < now() - interval '2 years' THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid'); -- M-7: not ahead of now, not past the log's 2 years
      END IF;
      v_emergency := coalesce((p_values ->> 'emergency')::boolean, false);
      v_target := (SELECT u.id FROM public.users AS u WHERE u.id = (p_values ->> 'target_user_id')::uuid);
      PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_le_request'), -- M-4: one create at a time per request
        pg_catalog.hashtext(concat_ws('|', v_at, p_values ->> 'jurisdiction', p_values ->> 'legal_basis', p_values ->> 'scope',
                                      v_emergency, v_target)));
      SELECT r.* INTO q FROM public.law_enforcement_requests AS r
       WHERE r.received_at = v_at AND r.jurisdiction = p_values ->> 'jurisdiction'
         AND r.legal_basis = p_values ->> 'legal_basis' AND r.scope = p_values ->> 'scope'
         AND r.emergency = v_emergency AND r.target_user_id IS NOT DISTINCT FROM v_target
       ORDER BY r.created_at, r.id LIMIT 1;
      IF q.id IS NOT NULL THEN
        IF q.decision = v_decision AND q.disclosed_categories = v_cats AND (q.user_notified_at IS NOT NULL OR NOT v_notify) THEN
          RETURN pg_catalog.jsonb_build_object('ok', true, 'id', q.id); -- the same request, every input the same: a replay
        END IF;
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'exists', 'id', q.id); -- decide it through p_request
      END IF;
      INSERT INTO public.law_enforcement_requests (received_at, jurisdiction, legal_basis, scope, emergency, target_user_id,
                                                   decision, disclosed_categories, decided_by, decided_at, user_notified_at)
      VALUES (v_at, p_values ->> 'jurisdiction', p_values ->> 'legal_basis', p_values ->> 'scope', v_emergency, v_target,
              v_decision, v_cats, CASE WHEN v_decision <> 'pending' THEN p_actor END,
              CASE WHEN v_decision <> 'pending' THEN now() END, CASE WHEN v_notify THEN now() END)
      RETURNING id INTO v_id;
    ELSE
      SELECT r.* INTO q FROM public.law_enforcement_requests AS r WHERE r.id = p_request FOR UPDATE;
      IF q.id IS NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
      END IF;
      IF q.decision = v_decision AND q.disclosed_categories = v_cats THEN
        IF q.user_notified_at IS NOT NULL OR NOT v_notify THEN
          RETURN pg_catalog.jsonb_build_object('ok', true, 'id', q.id); -- the same decision again: a replay
        END IF;
        UPDATE public.law_enforcement_requests AS r SET user_notified_at = now() -- M-3: the notice alone
         WHERE r.id = q.id
        RETURNING r.id INTO v_id;
      ELSE
        IF q.decision IN ('disclosed', 'partly_disclosed')
           AND NOT (v_decision IN ('disclosed', 'partly_disclosed') AND v_cats @> q.disclosed_categories) THEN
          RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'already_disclosed'); -- M-2: what was disclosed stays
        END IF;
        UPDATE public.law_enforcement_requests AS r
           SET decision = v_decision, disclosed_categories = v_cats, decided_by = p_actor, decided_at = now(),
               user_notified_at = CASE WHEN v_notify THEN coalesce(r.user_notified_at, now()) ELSE r.user_notified_at END
         WHERE r.id = q.id
        RETURNING r.id INTO v_id;
      END IF;
    END IF;
  EXCEPTION WHEN check_violation OR not_null_violation OR invalid_text_representation OR datetime_field_overflow
               OR invalid_datetime_format OR invalid_parameter_value THEN -- Task 8: a list that is not one too
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END;
  PERFORM private.dating_audit(p_actor, NULL, 'law_enforcement_request', NULL,
    pg_catalog.jsonb_build_object('decision', v_decision));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'id', v_id);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- §6.6: the quarterly transparency summary over [p_from, p_to): requests
-- by country and decision (and how many were met in whole or part), by
-- country and type (fix round 1, M-1: emergency or legal process),
-- reports by category, actions taken, appeals and how many were
-- overturned. Counts only; no person, no case.
CREATE OR REPLACE FUNCTION private.dating_transparency_summary(p_from date, p_to date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  -- The window's dates are read in the session's time zone (UTC on Supabase).
  WITH w AS (SELECT p_from::timestamptz AS lo, p_to::timestamptz AS hi)
  SELECT pg_catalog.jsonb_build_object(
    'from', p_from, 'to', p_to,
    'requests', coalesce((SELECT pg_catalog.jsonb_object_agg(x.jurisdiction, x.decisions)
                            FROM (SELECT r.jurisdiction, pg_catalog.jsonb_object_agg(r.decision, r.n) AS decisions
                                    FROM (SELECT q.jurisdiction, q.decision, count(*) AS n
                                            FROM public.law_enforcement_requests AS q, w
                                           WHERE q.received_at >= w.lo AND q.received_at < w.hi
                                           GROUP BY 1, 2) AS r
                                   GROUP BY r.jurisdiction) AS x), '{}'::jsonb),
    'request_types', coalesce((SELECT pg_catalog.jsonb_object_agg(x.jurisdiction, x.types)
                                 FROM (SELECT r.jurisdiction, pg_catalog.jsonb_object_agg(r.type, r.n) AS types
                                         FROM (SELECT q.jurisdiction, CASE WHEN q.emergency THEN 'emergency' ELSE 'legal_process' END AS type,
                                                      count(*) AS n
                                                 FROM public.law_enforcement_requests AS q, w
                                                WHERE q.received_at >= w.lo AND q.received_at < w.hi
                                                GROUP BY 1, 2) AS r
                                        GROUP BY r.jurisdiction) AS x), '{}'::jsonb),
    'requests_met', (SELECT count(*) FROM public.law_enforcement_requests AS q, w
                      WHERE q.received_at >= w.lo AND q.received_at < w.hi
                        AND q.decision IN ('disclosed', 'partly_disclosed')),
    'reports', coalesce((SELECT pg_catalog.jsonb_object_agg(x.category, x.n)
                           FROM (SELECT r.category, count(*) AS n FROM public.dating_reports AS r, w
                                  WHERE r.created_at >= w.lo AND r.created_at < w.hi GROUP BY 1) AS x), '{}'::jsonb),
    'actions', coalesce((SELECT pg_catalog.jsonb_object_agg(x.restriction_type, x.n)
                           FROM (SELECT a.restriction_type, count(*) AS n FROM public.dating_account_restrictions AS a, w
                                  WHERE a.created_at >= w.lo AND a.created_at < w.hi AND a.source <> 'carried_over'
                                  GROUP BY 1) AS x), '{}'::jsonb),
    -- W7 final server fix (M-11): the same actions by where they came from
    -- (a moderator's decision, a report's automatic step, a hash hit, W4's
    -- age check); carried ones are the same decision and left out.
    'actions_by_source', coalesce((SELECT pg_catalog.jsonb_object_agg(y.source, y.types)
                                     FROM (SELECT x.source, pg_catalog.jsonb_object_agg(x.restriction_type, x.n) AS types
                                             FROM (SELECT a.source, a.restriction_type, count(*) AS n
                                                     FROM public.dating_account_restrictions AS a, w
                                                    WHERE a.created_at >= w.lo AND a.created_at < w.hi AND a.source <> 'carried_over'
                                                    GROUP BY 1, 2) AS x
                                            GROUP BY x.source) AS y), '{}'::jsonb),
    'appeals', (SELECT count(*) FROM public.dating_appeals AS a, w WHERE a.submitted_at >= w.lo AND a.submitted_at < w.hi),
    'overturned', (SELECT count(*) FROM public.dating_appeals AS a, w
                    WHERE a.submitted_at >= w.lo AND a.submitted_at < w.hi AND a.state = 'accepted'));
$$;

-- A read that counts is a write (Task 5): VOLATILE.
CREATE OR REPLACE FUNCTION public.moderation_transparency_summary(p_actor uuid, p_from date, p_to date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 8: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_to <= p_from OR p_to - p_from > 366 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'summary', private.dating_transparency_summary(p_from, p_to));
END;
$$;

-- ---------------------------------------------------------------------
-- 3b. The CSAM hold lift (owner 2026-11-22): a hash hit's hold (or the
--     same hold carried past a deletion) is lifted only by the safety
--     owner, after review, with a written reason, for a false-positive
--     hit. Fix round 2: a CSAM hold is any moderation_hold of category
--     csam (a hash hit's, a report's or a carried one); nothing else ends
--     it, and no other hold is ever folded into it. Listed for the owner alone, never the owner's own; the
--     person's setup lock first, then the row (W7a's order); audited once
--     with its reason (a replay answers as the first call did); counted
--     (dating.moderation.csam_lift, listed in W7a's health, R-57). A
--     carried hold's record ends with it. Spec 1's account hold is its
--     own matter and is never touched here; the image is never shown.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.moderation_csam_holds(p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v_hmac text;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  v_hmac := public.dating_phone_hmac_for_user(p_actor);
  -- Each live CSAM hold: its id, since when, whether it was carried, and
  -- Spec 1's escalations of the person's matched uploads (id, status and
  -- date only), so the owner can tie the hold to the review it follows.
  RETURN pg_catalog.jsonb_build_object('ok', true, 'holds', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', r.id, 'since', r.starts_at,
             'carried', r.source = 'carried_over', 'case_id', r.case_id, -- fix round 2: a report's CSAM hold has its case
             'escalations', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', e.id, 'status', e.status,
                                                                  'created_at', e.created_at) ORDER BY e.created_at, e.id)
                                        FROM public.safety_escalations AS e
                                       WHERE e.kind = 'csam_match' AND e.user_id = r.user_id), '[]'::jsonb))
             ORDER BY r.starts_at, r.id)
      FROM public.dating_account_restrictions AS r
     WHERE r.restriction_type = 'moderation_hold' AND r.category = 'csam' -- fix round 2: any hold of category csam
       AND r.lifted_at IS NULL AND (r.ends_at IS NULL OR r.ends_at > now())
       AND r.user_id <> p_actor
       AND (v_hmac IS NULL OR public.dating_phone_hmac_for_user(r.user_id) IS DISTINCT FROM v_hmac)), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_lift_csam_hold(p_actor uuid, p_restriction uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v_reason constant text := NULLIF(btrim(coalesce(p_reason, '')), '');
  v_user uuid;
  v_hmac text;
  r public.dating_account_restrictions;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  IF p_restriction IS NULL OR v_reason IS NULL OR char_length(v_reason) > 1000 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  BEGIN -- a lock not had in 2 s answers busy (counted)
    SELECT x.user_id INTO v_user FROM public.dating_account_restrictions AS x WHERE x.id = p_restriction;
    IF v_user IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'hold_unavailable');
    END IF;
    -- Never the owner's own hold (by account or by number), counted.
    v_hmac := public.dating_phone_hmac_for_user(p_actor);
    IF v_user = p_actor OR (v_hmac IS NOT NULL AND public.dating_phone_hmac_for_user(v_user) IS NOT DISTINCT FROM v_hmac) THEN
      PERFORM private.bump_metric_internal('dating.moderation.party_refused');
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'hold_unavailable');
    END IF;
    PERFORM private.dating_lock_setup(v_user); -- the person's setup lock, then the row
    SELECT x.* INTO r FROM public.dating_account_restrictions AS x WHERE x.id = p_restriction FOR UPDATE;
    IF r.id IS NULL OR r.restriction_type <> 'moderation_hold'
       OR r.category IS DISTINCT FROM 'csam' THEN -- fix round 2: any hold of category csam, whatever placed it
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'hold_unavailable');
    END IF;
    IF r.lifted_at IS NOT NULL OR (r.ends_at IS NOT NULL AND r.ends_at <= now()) THEN
      -- This owner's own lift, answered again; anything else is no hold.
      IF private.dating_moderation_replayed(p_actor, NULL, 'lift_csam_hold', pg_catalog.jsonb_build_object('restriction', r.id)) THEN
        RETURN pg_catalog.jsonb_build_object('ok', true);
      END IF;
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'hold_unavailable');
    END IF;
    UPDATE public.dating_account_restrictions AS x SET lifted_at = now() WHERE x.id = r.id;
    IF r.carried_from IS NOT NULL THEN
      UPDATE public.enforcement_records AS er SET effect_until = now()
       WHERE er.id = r.carried_from AND (er.effect_until IS NULL OR er.effect_until > now());
    END IF;
    PERFORM private.dating_audit(p_actor, NULL, 'lift_csam_hold', r.user_id,
                                 pg_catalog.jsonb_build_object('restriction', r.id, 'reason', v_reason));
    PERFORM private.bump_metric_internal('dating.moderation.csam_lift');
    RETURN pg_catalog.jsonb_build_object('ok', true);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- ---------------------------------------------------------------------
-- 3c. (§4.8, W6 T8 carry) What a live restriction or a live enforcement
--     record still needs from its case: the purge keeps the case, and with
--     it the case's reports, audit rows and escalations, while either
--     lasts (the reports step's own guard reads the case, so a case
--     purged first would free its reports a run later).
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS dating_account_restrictions_case_idx
  ON public.dating_account_restrictions (case_id) WHERE case_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS enforcement_records_case_idx -- fix round 1 (M-8)
  ON public.enforcement_records (case_id) WHERE case_id IS NOT NULL;
-- Fix round 1 (I-2, M-12): a case still open or in review needs its rows
-- (P-3, R-66: the clock never empties a moderator's queue), and an appeal
-- case needs its own while the restriction it decided lasts.
CREATE OR REPLACE FUNCTION private.dating_case_needed(p_case uuid, p_now timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_case IS NOT NULL
     AND (EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                   WHERE c.id = p_case AND c.state IN ('open', 'in_review'))
          OR EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                       JOIN public.dating_appeals AS a ON a.id = c.appeal_id
                       JOIN public.dating_account_restrictions AS x ON x.id = a.restriction_id
                      WHERE c.id = p_case AND x.lifted_at IS NULL AND (x.ends_at IS NULL OR x.ends_at > p_now))
          OR EXISTS (SELECT 1 FROM public.dating_account_restrictions AS x
                   WHERE x.case_id = p_case AND x.lifted_at IS NULL AND (x.ends_at IS NULL OR x.ends_at > p_now))
          OR EXISTS (SELECT 1 FROM public.enforcement_records AS k
                      WHERE k.case_id = p_case AND k.purge_after > p_now AND (k.effect_until IS NULL OR k.effect_until > p_now)));
$$;

-- ---------------------------------------------------------------------
-- 3d. (Fix round 1, (b)) A case's escalations, for the console: any
--     moderator who can see the case (routing, parties) reads each one's
--     kind and date and whether they recorded it; the reference (an
--     agency's own number) is the safety owner's and the recorder's
--     alone. A party is refused, counted. A read that counts: VOLATILE.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.moderation_case_escalations(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  c := private.dating_case_for(v_mod, p_case);
  IF c.id IS NULL THEN
    IF private.dating_case_party(p_actor, p_case) THEN
      PERFORM private.bump_metric_internal('dating.moderation.party_refused');
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'escalations', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('kind', e.kind, 'recorded_at', e.recorded_at,
             'mine', e.recorded_by = p_actor)
           || CASE WHEN v_mod.role = 'safety_owner' OR e.recorded_by = p_actor
                   THEN pg_catalog.jsonb_build_object('reference', e.reference) ELSE '{}'::jsonb END
           ORDER BY e.recorded_at, e.id)
      FROM public.dating_escalations AS e WHERE e.case_id = c.id), '[]'::jsonb));
END;
$$;

-- ---------------------------------------------------------------------
-- 3e. (Fix round 5, owner 2026-11-22) Close: no ID came. An awaiting case
--     is decided (no_id_received; its reports upheld) and the age check
--     stays: the person is not freed. Every console-write rule: not a
--     moderator counted, the setup lock then the case row, a party or an
--     unrouted moderator refused (counted), 2 s then busy (counted), the
--     same moderator again a replay, audited once, counted
--     (dating.moderation.no_id, listed in health). The age check can still
--     be lifted later by Lift hold on the decided case (R-56).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.moderation_close_no_id(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- a lock not had in 2 s answers busy (counted)
    c := private.dating_case_lock(v_mod, p_case);
    IF c.id IS NOT NULL AND c.outcome = 'no_id_received' AND private.dating_moderation_replayed(p_actor, c.id, 'close_no_id') THEN
      RETURN pg_catalog.jsonb_build_object('ok', true); -- a replay
    END IF;
    -- Round 3: an open id_check case whose asked check is live. Round 4
    -- (N3-1): or, the person deleted while it was open, whose check lives
    -- on as the deletion's record (the number stays checked).
    IF c.id IS NULL OR c.kind <> 'id_check' OR c.state NOT IN ('open', 'in_review')
       OR ((private.dating_case_id_check(c.id)).id IS NULL AND NOT private.dating_case_id_record_live(c.id)) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    v := private.dating_close_case(c.id, p_actor, 'no_id_received');
    IF NOT (v ->> 'ok')::boolean THEN
      RETURN v;
    END IF;
    PERFORM private.dating_audit(p_actor, c.id, 'close_no_id', c.target_user_id);
    PERFORM private.bump_metric_internal('dating.moderation.no_id');
    RETURN pg_catalog.jsonb_build_object('ok', true);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- ---------------------------------------------------------------------
-- 3f. (W7 final server fix, I-1) One ID-check design. Ask for ID always
--     writes its own age check, owned by its case (never W4's, a carried
--     one or another case's), with a short reference code the person sees
--     and puts in the ID email; the case keeps it in
--     awaiting_id_restriction. Every ID action keys on that check being
--     live, never on the case's state.
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_account_restrictions ADD COLUMN IF NOT EXISTS id_check_code text;
ALTER TABLE public.dating_account_restrictions DROP CONSTRAINT IF EXISTS dating_account_restrictions_id_check_code_check;
-- 8 characters from 31 (no 0/O/1/I/L): random, never derived from an id or
-- a number; only on an age check.
ALTER TABLE public.dating_account_restrictions ADD CONSTRAINT dating_account_restrictions_id_check_code_check
  CHECK (id_check_code IS NULL OR (restriction_type = 'age_review' AND id_check_code ~ '^[2-9A-HJKMNP-Z]{8}$'));
-- Unique while live.
CREATE UNIQUE INDEX IF NOT EXISTS dating_account_restrictions_id_check_code_live
  ON public.dating_account_restrictions (id_check_code) WHERE id_check_code IS NOT NULL AND lifted_at IS NULL;

-- Round 3 (re-review 2; the controller's ruling): the ID check is its own
-- case. Ask for ID opens a case of kind id_check for the same person,
-- moves the open underage_risk reports and the asked age check there, and
-- leaves the original case its other reports. No report joins an
-- id_check case (a report joins report cases only); a person has at most
-- one open id_check case beside their one open report case.
ALTER TABLE public.dating_moderation_cases DROP CONSTRAINT IF EXISTS dating_moderation_cases_kind_check;
ALTER TABLE public.dating_moderation_cases ADD CONSTRAINT dating_moderation_cases_kind_check
  CHECK (kind IN ('report', 'photo', 'verification', 'signal', 'appeal', 'csam_hit', 'id_check'));
ALTER TABLE public.dating_moderation_cases ADD COLUMN IF NOT EXISTS origin_case_id uuid
  REFERENCES public.dating_moderation_cases (id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS dating_moderation_cases_origin_idx ON public.dating_moderation_cases (origin_case_id)
  WHERE origin_case_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS dating_moderation_cases_open_id_check_idx ON public.dating_moderation_cases (target_user_id)
  WHERE kind = 'id_check' AND state IN ('open', 'in_review') AND target_user_id IS NOT NULL;

CREATE OR REPLACE FUNCTION private.dating_id_check_code()
RETURNS text
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT string_agg(substr('23456789ABCDEFGHJKMNPQRSTUVWXYZ', (pg_catalog.get_byte(x.b, g.i) % 31) + 1, 1), '' ORDER BY g.i)
    FROM (SELECT extensions.gen_random_bytes(8) AS b) AS x, generate_series(0, 7) AS g(i);
$$;

-- The case's asked age check while it is live (its own row, on this case,
-- not lifted, not ended); NULL otherwise.
CREATE OR REPLACE FUNCTION private.dating_case_id_check(p_case uuid)
RETURNS public.dating_account_restrictions
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT r.* FROM public.dating_moderation_cases AS c
    JOIN public.dating_account_restrictions AS r ON r.id = c.awaiting_id_restriction
   WHERE c.id = p_case AND r.case_id = c.id AND r.restriction_type = 'age_review' AND r.lifted_at IS NULL
     AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now());
$$;

-- What the console reads: {state: 'awaiting' | 'no_id' | null,
-- restriction_live, code, outcome}. Confirm a minor clears the path, so a
-- confirmed minor's case reads null. Round 3: read on an id_check case
-- (outcome is that case's own).
CREATE OR REPLACE FUNCTION private.dating_case_id_check_json(p_case uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT pg_catalog.jsonb_build_object(
           'state', CASE WHEN r.id IS NULL THEN NULL WHEN c.outcome = 'no_id_received' THEN 'no_id' ELSE 'awaiting' END,
           'restriction_live', r.id IS NOT NULL,
           'code', r.id_check_code,
           'outcome', c.outcome)
    FROM public.dating_moderation_cases AS c
    LEFT JOIN LATERAL (SELECT (private.dating_case_id_check(c.id)).*) AS r ON true
   WHERE c.id = p_case;
$$;

-- Round 4 (N3-1): the case's asked check left as an enforcement record by
-- a deletion (its row gone with the account), still in force.
CREATE OR REPLACE FUNCTION private.dating_case_id_record_live(p_case uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                   JOIN public.enforcement_records AS er ON er.source_restriction_id = c.awaiting_id_restriction
                  WHERE c.id = p_case AND er.case_id = c.id AND er.scope = 'dating' AND er.restriction_type = 'age_review'
                    AND (er.effect_until IS NULL OR er.effect_until > now()) AND er.purge_after > now());
$$;

-- Ends the case's asked age check: the row (and a carried row's record),
-- or, when the person deleted while it waited, the record it left. Never
-- another age check. Answers how many rows it lifted.
CREATE OR REPLACE FUNCTION private.dating_end_id_check(p_case uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
  v_n integer;
BEGIN
  SELECT c.awaiting_id_restriction INTO v_id FROM public.dating_moderation_cases AS c WHERE c.id = p_case;
  IF v_id IS NULL THEN
    RETURN 0;
  END IF;
  WITH lifted AS (
    UPDATE public.dating_account_restrictions AS r SET lifted_at = now()
     WHERE r.id = v_id AND r.case_id = p_case AND r.restriction_type = 'age_review' AND r.lifted_at IS NULL
       AND (r.ends_at IS NULL OR r.ends_at > now())
    RETURNING r.carried_from),
  ended AS (
    UPDATE public.enforcement_records AS er SET effect_until = now()
      FROM lifted WHERE er.id = lifted.carried_from AND (er.effect_until IS NULL OR er.effect_until > now())
    RETURNING er.id)
  SELECT count(*) INTO v_n FROM lifted;
  UPDATE public.enforcement_records AS er SET effect_until = now()
   WHERE er.source_restriction_id = v_id AND er.case_id = p_case AND er.scope = 'dating' AND er.restriction_type = 'age_review'
     AND (er.effect_until IS NULL OR er.effect_until > now());
  RETURN v_n;
END;
$$;

-- Ask for ID's own check: a new age check on the case, never one reused,
-- written with its code (a clash with a live code draws again).
CREATE OR REPLACE FUNCTION private.dating_place_id_check(p_user uuid, p_case uuid, p_actor uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
BEGIN
  PERFORM private.dating_lock_setup(p_user);
  FOR v_try IN 1..8 LOOP
    BEGIN
      INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, decided_by,
                                                      appealable, id_check_code)
      VALUES (p_user, 'age_review', 'underage_risk', 'moderator', p_case, p_actor, false, private.dating_id_check_code())
      RETURNING id INTO v_id;
      RETURN v_id;
    EXCEPTION WHEN unique_violation THEN
      IF v_try = 8 THEN
        RAISE;
      END IF;
    END;
  END LOOP;
  RETURN NULL;
END;
$$;

-- (W7 final server fix, I-6) A closer look a deletion left on the
-- person's number, live at [p_at]: generation leaves them out on return
-- (read-time, as the open-report exclusion; nothing to carry). Its own
-- function, so generation's own text reads no number (W5's rule).
CREATE OR REPLACE FUNCTION private.dating_closer_look_carried(p_user uuid, p_at timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.enforcement_records AS er
                  WHERE er.scope = 'dating' AND er.restriction_type = 'under_review'
                    AND er.phone_hmac = public.dating_phone_hmac_for_user(p_user)
                    AND (er.effect_until IS NULL OR er.effect_until > p_at) AND er.purge_after > p_at);
$$;

-- Round 2 (N-1): Lift the case's holds, the explicit hold lift: an open
-- case's interim holds and report age checks (a carried one's record
-- too), never its asked check, never a CSAM hold. (Round 3: Lift hold on
-- a case that is not an ID check does the same; this stays the explicit
-- one.)
-- Every console-write rule: not a moderator counted, the setup lock then
-- the case row, a party or an unrouted moderator refused, 2 s then busy,
-- a replay answered with the first count, audited once (lift_hold with
-- holds: true).
CREATE OR REPLACE FUNCTION public.moderation_lift_case_holds(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v_n integer;
  v_rows bigint;
  v_first jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- a lock not had in 2 s answers busy (counted)
    c := private.dating_case_lock(v_mod, p_case);
    IF c.id IS NULL OR c.target_user_id IS NULL OR c.kind = 'appeal' OR c.state NOT IN ('open', 'in_review') THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    WITH lifted AS (
      UPDATE public.dating_account_restrictions AS r SET lifted_at = now()
       WHERE r.user_id = c.target_user_id AND r.case_id = c.id AND r.lifted_at IS NULL
         AND r.category IS DISTINCT FROM 'csam' AND r.source <> 'csam_hash'
         AND r.id IS DISTINCT FROM c.awaiting_id_restriction AND r.id_check_code IS NULL
         AND (r.restriction_type = 'moderation_hold' OR (r.restriction_type = 'age_review' AND r.decided_by IS NULL))
      RETURNING r.carried_from),
    ended AS (
      UPDATE public.enforcement_records AS er SET effect_until = now()
        FROM lifted WHERE er.id = lifted.carried_from AND (er.effect_until IS NULL OR er.effect_until > now())
      RETURNING er.id)
    SELECT count(*) INTO v_n FROM lifted;
    v_rows := (SELECT count(*) FROM public.dating_account_restrictions AS r WHERE r.case_id = c.id);
    IF v_n = 0 THEN
      SELECT a.detail INTO v_first FROM public.dating_moderation_actions AS a
       WHERE a.actor_id = p_actor AND a.case_id = c.id AND a.action = 'lift_hold' AND a.detail ? 'holds'
       ORDER BY a.created_at DESC, a.id DESC LIMIT 1;
      IF v_first ? 'lifted' AND (v_first ->> 'rows')::bigint IS NOT DISTINCT FROM v_rows THEN
        RETURN pg_catalog.jsonb_build_object('ok', true, 'lifted', v_first -> 'lifted'); -- a replay
      END IF;
    END IF;
    PERFORM private.dating_audit(p_actor, c.id, 'lift_hold', c.target_user_id,
                                 pg_catalog.jsonb_build_object('lifted', v_n, 'rows', v_rows, 'holds', true));
    RETURN pg_catalog.jsonb_build_object('ok', true, 'lifted', v_n);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- ---------------------------------------------------------------------
-- 3g. (W7 final server fix, I-3, M-7) The queue by kind: a kind filters
--     before the limit; round 3: 'id_check' is the id_check cases, open or
--     with their check live (a decided No ID came case too); no kind is the
--     open cases of every kind and those. Parties and routing are
--     asked row by row in queue order, and only until the page is full
--     (one more tells has_more). Each row carries id_check.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.moderation_queue(uuid, integer);
CREATE OR REPLACE FUNCTION public.moderation_queue(p_actor uuid, p_limit integer DEFAULT 50, p_kind text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v_limit constant integer := greatest(1, least(coalesce(p_limit, 50), 200));
  v_cases jsonb := '[]'::jsonb;
  v_n integer := 0;
  v_more boolean := false;
  c public.dating_moderation_cases;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF p_kind IS NOT NULL AND p_kind NOT IN ('report', 'appeal', 'signal', 'photo', 'verification', 'csam_hit', 'id_check') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR c IN
    SELECT x.* FROM public.dating_moderation_cases AS x
     WHERE (p_kind IS NULL OR x.kind = p_kind)
       AND (x.state IN ('open', 'in_review') -- round 3: and an id_check case whose check is live (No ID came)
            OR (x.kind = 'id_check' AND (private.dating_case_id_check(x.id)).id IS NOT NULL))
     ORDER BY x.priority, x.sla_due_at NULLS LAST, x.created_at, x.id
  LOOP
    CONTINUE WHEN private.dating_case_party(v_mod.user_id, c.id); -- Task 5 fix round 1 (I-2)
    CONTINUE WHEN NOT v_mod.sensitive_routing_allowed AND coalesce(private.dating_case_needs_sensitive_routing(c.id), true);
    IF v_n = v_limit THEN
      v_more := true;
      EXIT;
    END IF;
    v_cases := v_cases || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'id', c.id, 'kind', c.kind, 'priority', c.priority,
      'state', CASE WHEN private.dating_case_awaiting_id(c.state, c.awaiting_id_since) THEN 'awaiting_id' ELSE c.state END,
      'signal_kind', c.signal_kind,
      'category', (SELECT r.category FROM public.dating_reports AS r WHERE r.case_id = c.id ORDER BY r.priority, r.created_at LIMIT 1),
      'reports', (SELECT count(*) FROM public.dating_reports AS r WHERE r.case_id = c.id),
      'sla_due_at', c.sla_due_at, 'created_at', c.created_at,
      'mine', c.assigned_to = p_actor, 'claimed', c.assigned_to IS NOT NULL,
      'gone', c.target_user_id IS NULL,
      'id_check', CASE WHEN c.kind = 'id_check' THEN private.dating_case_id_check_json(c.id) END));
    v_n := v_n + 1;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'cases', v_cases, 'has_more', v_more);
END;
$$;

-- ---------------------------------------------------------------------
-- 3h. (W7 final server fix, M-2) An SLA alert the webhook refused: each
--     post's request id is kept, and the next run reads pg_net's answers
--     for them (4xx/5xx, timed out, an error) and counts each
--     (dating.sla.alert_rejected). Ids older than a day are dropped
--     (pg_net keeps its answers for hours).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS private.dating_sla_alert_requests (
  request_id bigint PRIMARY KEY,
  sent_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 3i. (W7 final server fix, M-5) A report filed before W7a and still open
--     has no case, so no console lists it: each gets its person's open
--     case (the report's own join). Run once below; idempotent.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_backfill_report_cases()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_report uuid;
  v_n integer := 0;
BEGIN
  FOR v_report IN
    SELECT r.id FROM public.dating_reports AS r
     WHERE r.case_id IS NULL AND r.state IN ('open', 'in_review')
       AND (r.target_user_id IS NOT NULL OR r.target_phone_hmac IS NOT NULL)
     ORDER BY r.created_at, r.id
  LOOP
    PERFORM private.dating_report_case(v_report);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ---------------------------------------------------------------------
-- 3j. (W7 final server fix, I-9) The W7 production gate, on the flag that
--     makes Report reachable (the owner signs this row). The anchor is the
--     W6 text's end; a missing anchor raises (no silent gate loss).
-- ---------------------------------------------------------------------
DO $gate$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'dating_match_messaging') THEN
    RAISE EXCEPTION 'W7c: the dating_match_messaging gate row is missing';
  END IF;
  UPDATE private.flag_production_gates
     SET gate = gate || '; Spec 2 W7 gate: the safety owner, a moderator who reads Twi, Ga and Pidgin, and out-of-hours P0 cover named and trained on DATING_MODERATION_RUNBOOK.md; counsel''s signature on DATING_LAW_ENFORCEMENT_POLICY.md; the report''s SLA sentence matching the staffed hours (private.dating_report_sla_due)'
   WHERE flag_key = 'dating_match_messaging' AND gate NOT LIKE '%Spec 2 W7 gate%';
  IF NOT EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'dating_match_messaging' AND gate LIKE '%Spec 2 W7 gate%') THEN
    RAISE EXCEPTION 'W7c: the W7 gate was not written on dating_match_messaging';
  END IF;
END $gate$;

-- ---------------------------------------------------------------------
-- 3k. (W7 final server fix, M-4) The two W7 crons off the quarter hour
--     (:00/:15/:30/:45 carry six other jobs, one of which writes the same
--     enrolment rows).
-- ---------------------------------------------------------------------
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = 'cron') THEN
    PERFORM cron.unschedule(j.jobid) FROM cron.job AS j WHERE j.jobname IN ('release-dating-suspensions', 'dating-moderation-sla');
    PERFORM cron.schedule('release-dating-suspensions', '4-59/15 * * * *', $c$SELECT private.dating_release_expired_suspensions()$c$);
    PERFORM cron.schedule('dating-moderation-sla', '11-59/15 * * * *', $c$SELECT public.dating_moderation_sla_check()$c$);
  END IF;
END $cron$;

-- ---------------------------------------------------------------------
-- 4. Re-created from their live bodies; only the lines marked
--    "-- Spec 2 W7c" change.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_purge_steps()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT ARRAY['matches', 'introductions', 'pair_markers', -- Spec 2 W7a: and the report evidence and reports
               'report_evidence', 'reports', 'moderation_cases', 'opener_hashes', -- Spec 2 W7a
               'safety_events', 'safety_outbox', 'rate_limits', 'block_hmacs', 'enforcement_records',
               'session_context', 'moderation_actions', 'escalations', 'law_enforcement_requests']; -- Spec 2 W7c
$function$;

CREATE OR REPLACE FUNCTION private.dating_purge_step(p_step text, p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  v_n integer;
  v_try integer;
  v_ids uuid[];
BEGIN
  FOR v_try IN 1..3 LOOP
    BEGIN
      CASE p_step
      -- A closed match after its 30-day window, with its messages (cascade),
      -- unless an open case holds it (§4.8 "unless a report holds it"), or
      -- (Ruling P-2, W6b N-4) a safety event about it is still inside the
      -- 7-day evidence window: a deleted recipient is then still counted
      -- once by the match, never once per event. Fix round 1 (M-9): the
      -- rows are locked first, skipping one another job holds (a case being
      -- filed holds it key-share), and the holds are tested again by a new
      -- statement, which sees every case committed before the lock.
      WHEN 'matches' THEN
        SELECT coalesce(pg_catalog.array_agg(y.id), '{}') INTO v_ids
          FROM (SELECT x.id FROM public.dating_matches AS x
                 WHERE x.state <> 'active' AND x.evidence_until < p_now
                 AND NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                                  WHERE c.match_id = x.id AND c.state IN ('open', 'in_review'))
                 AND NOT EXISTS (SELECT 1 FROM public.dating_case_matches AS l -- Spec 2 W7a (W6 M-16): every match a case links
                                   JOIN public.dating_moderation_cases AS c ON c.id = l.case_id -- Spec 2 W7a
                                  WHERE l.match_id = x.id AND c.state IN ('open', 'in_review')) -- Spec 2 W7a
                 AND NOT EXISTS (SELECT 1 FROM public.dating_safety_events AS e
                                  WHERE e.match_id = x.id AND e.created_at > p_now - interval '7 days')
                 LIMIT 5000
                   FOR UPDATE OF x SKIP LOCKED) AS y;
        DELETE FROM public.dating_matches AS x
         WHERE x.id = ANY (v_ids)
           AND x.state <> 'active' AND x.evidence_until < p_now
                 AND NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                                  WHERE c.match_id = x.id AND c.state IN ('open', 'in_review'))
                 AND NOT EXISTS (SELECT 1 FROM public.dating_case_matches AS l -- Spec 2 W7a
                                   JOIN public.dating_moderation_cases AS c ON c.id = l.case_id -- Spec 2 W7a
                                  WHERE l.match_id = x.id AND c.state IN ('open', 'in_review')) -- Spec 2 W7a
                 AND NOT EXISTS (SELECT 1 FROM public.dating_safety_events AS e
                                  WHERE e.match_id = x.id AND e.created_at > p_now - interval '7 days');
      -- A resolved introduction keeps only its ids, pair key, state and
      -- dates 30 days on (its interest actions go).
      WHEN 'introductions' THEN
        WITH old AS (
          SELECT i.id FROM public.dating_introductions AS i
           WHERE i.state IN ('passed', 'matched', 'expired', 'invalidated')
             AND greatest(i.expires_at, i.created_at) < p_now - interval '30 days'
             AND (i.low_action IS NOT NULL OR i.high_action IS NOT NULL OR cardinality(i.reasons) > 0 OR i.rank_detail IS NOT NULL
                  OR EXISTS (SELECT 1 FROM public.dating_interest_actions AS a WHERE a.introduction_id = i.id))
           LIMIT 5000
        ), gone AS (
          DELETE FROM public.dating_interest_actions AS a USING old WHERE a.introduction_id = old.id
        )
        UPDATE public.dating_introductions AS i SET low_action = NULL, high_action = NULL, reasons = '{}', rank_detail = NULL
          FROM old WHERE i.id = old.id;
      -- Spec 2 W7a (§4.8): evidence until its case closes + 180 days, or while a
      -- Spec 2 W7a restriction or a carried record from that case lasts.
      WHEN 'report_evidence' THEN -- Spec 2 W7a
        DELETE FROM public.dating_report_evidence AS e -- Spec 2 W7a
         USING public.dating_reports AS r, public.dating_moderation_cases AS c -- Spec 2 W7a
         WHERE r.id = e.report_id AND c.id = r.case_id AND c.state IN ('decided', 'closed') -- Spec 2 W7a
           AND coalesce(c.decided_at, c.created_at) < p_now - interval '180 days' -- Spec 2 W7a
           AND NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS x -- Spec 2 W7a
                            WHERE x.case_id = c.id AND x.lifted_at IS NULL AND (x.ends_at IS NULL OR x.ends_at > p_now)) -- Spec 2 W7a
           AND NOT EXISTS (SELECT 1 FROM public.enforcement_records AS k -- Spec 2 W7a
                            WHERE k.case_id = c.id AND k.purge_after > p_now -- Spec 2 W7a
                              AND (k.effect_until IS NULL OR k.effect_until > p_now)); -- Spec 2 W7a
      -- Spec 2 W7a (§4.8, W6 T8 carry): reports at 2 years (their evidence goes
      -- Spec 2 W7a with them); one whose case is still open stays (Ruling P-3).
      WHEN 'reports' THEN -- Spec 2 W7a
        DELETE FROM public.dating_reports AS r -- Spec 2 W7a
         WHERE r.created_at < p_now - interval '2 years' -- Spec 2 W7a
           AND NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS y -- Spec 2 W7a (fix round 1, M-2): nor while a
                            WHERE y.case_id = r.case_id AND y.lifted_at IS NULL AND (y.ends_at IS NULL OR y.ends_at > p_now)) -- Spec 2 W7a
           AND NOT EXISTS (SELECT 1 FROM public.enforcement_records AS k2 -- Spec 2 W7a restriction or a record from its case lasts (§4.8)
                            WHERE k2.case_id = r.case_id AND k2.purge_after > p_now -- Spec 2 W7a
                              AND (k2.effect_until IS NULL OR k2.effect_until > p_now)) -- Spec 2 W7a
           AND NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c -- Spec 2 W7a
                            WHERE c.id = r.case_id AND c.state IN ('open', 'in_review')); -- Spec 2 W7a
      WHEN 'pair_markers' THEN
        DELETE FROM public.dating_pair_markers AS k WHERE k.purge_after < p_now;
      -- Carry 9: 2 years. Ruling P-3: a case still open or in review stays
      -- (a moderator's queue is never emptied by the clock).
      WHEN 'moderation_cases' THEN
        DELETE FROM public.dating_moderation_cases AS c
         WHERE c.created_at < p_now - interval '2 years' AND c.state NOT IN ('open', 'in_review') -- Spec 2 W7c (§4.8): nor while a
           AND NOT private.dating_case_needed(c.id, p_now); -- Spec 2 W7c live restriction or record from it lasts (its reports with it)
      WHEN 'opener_hashes' THEN
        DELETE FROM public.dating_opener_hashes AS k WHERE k.created_at < p_now - interval '30 days';
      -- Safety events after 90 days keep only their family, tier, rule and
      -- version (nobody, no match, no message). Ruling P-4: the source key
      -- (message id ':' rule) is replaced too, or it would still name the
      -- message, and through it both people.
      WHEN 'safety_events' THEN
        UPDATE public.dating_safety_events AS e
           SET at_risk_user_id = NULL, sender_user_id = NULL, match_id = NULL, message_id = NULL,
               source_event_key = 'anon:' || e.id::text
         WHERE e.created_at < p_now - interval '90 days'
           AND (e.at_risk_user_id IS NOT NULL OR e.sender_user_id IS NOT NULL OR e.match_id IS NOT NULL OR e.message_id IS NOT NULL
                OR e.source_event_key <> 'anon:' || e.id::text);
      WHEN 'safety_outbox' THEN
        DELETE FROM public.dating_message_safety_outbox AS o
         WHERE o.state = 'done' AND o.completed_at < p_now - interval '7 days';
      WHEN 'rate_limits' THEN
        DELETE FROM public.dating_rate_limits AS r WHERE r.window_started_at < p_now - interval '2 days';
      WHEN 'block_hmacs' THEN
        DELETE FROM public.dating_block_hmacs AS h WHERE h.purge_after < p_now;
      WHEN 'enforcement_records' THEN
        DELETE FROM public.enforcement_records AS r WHERE r.scope = 'dating' AND r.purge_after < p_now;
      WHEN 'session_context' THEN
        DELETE FROM public.dating_session_context AS c WHERE c.checked_at < p_now - interval '30 days';
      -- Spec 2 W7c (§4.8): the audit at 2 years: the append-only guard lets only
      -- Spec 2 W7c this step's delete through, and only rows 2 years old by the
      -- Spec 2 W7c clock (a later p_now never trips it); a row of a case a live
      -- Spec 2 W7c restriction or record still needs stays, as the case does.
      WHEN 'moderation_actions' THEN -- Spec 2 W7c
        PERFORM pg_catalog.set_config('attune.dating_audit_purge', 'on', true); -- Spec 2 W7c
        DELETE FROM public.dating_moderation_actions AS a WHERE a.id IN (SELECT y.id FROM public.dating_moderation_actions AS y -- Spec 2 W7c
         WHERE y.created_at < least(p_now, now()) - interval '2 years' -- Spec 2 W7c
           AND NOT private.dating_case_needed(y.case_id, p_now) LIMIT 5000); -- Spec 2 W7c (fix round 1, M-8): in batches, as matches
        GET DIAGNOSTICS v_n = ROW_COUNT; -- Spec 2 W7c: read before the setting is put back
        PERFORM pg_catalog.set_config('attune.dating_audit_purge', 'off', true); -- Spec 2 W7c
        RETURN pg_catalog.jsonb_build_object(p_step, v_n); -- Spec 2 W7c
      WHEN 'escalations' THEN -- Spec 2 W7c
        DELETE FROM public.dating_escalations AS e WHERE e.id IN (SELECT y.id FROM public.dating_escalations AS y -- Spec 2 W7c
         WHERE y.recorded_at < p_now - interval '2 years' -- Spec 2 W7c
           AND NOT private.dating_case_needed(y.case_id, p_now) LIMIT 5000); -- Spec 2 W7c (fix round 1, M-8)
      WHEN 'law_enforcement_requests' THEN -- Spec 2 W7c
        DELETE FROM public.law_enforcement_requests AS r WHERE r.received_at < p_now - interval '2 years'; -- Spec 2 W7c
      END CASE;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      RETURN pg_catalog.jsonb_build_object(p_step, v_n);
    EXCEPTION
      WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
        IF v_try < 3 THEN
          PERFORM private.bump_metric_internal('dating.purge.retried');
        ELSE
          PERFORM private.bump_metric_internal('dating.purge.failed.' || p_step);
          RETURN pg_catalog.jsonb_build_object(p_step, 'failed:' || SQLSTATE);
        END IF;
      -- Final server fix (M-5): a statement timeout (or a cancel) skips this
      -- step only, counted like any failure (OTHERS does not catch it).
      WHEN OTHERS OR query_canceled THEN
        PERFORM private.bump_metric_internal('dating.purge.failed.' || p_step);
        RETURN pg_catalog.jsonb_build_object(p_step, 'failed:' || SQLSTATE);
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object(p_step, 'failed:retries');
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_unavailable_state(p_user uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                  WHERE r.user_id = p_user AND r.restriction_type = 'suspended' AND r.lifted_at IS NULL
                    AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()))
      OR EXISTS (SELECT 1 FROM public.enforcement_records AS er
                  WHERE er.scope = 'dating' AND er.phone_hmac = public.dating_phone_hmac_for_user(p_user)
                    AND er.restriction_type = 'suspended' -- Spec 2 W7c: a carried hold or age check is its own state below
                    AND (er.effect_until IS NULL OR er.effect_until > now()) AND er.purge_after > now())
      OR EXISTS (SELECT 1 FROM auth.users AS a
                  WHERE a.id = p_user AND a.banned_until > now()) THEN 'restricted'
    WHEN EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                  WHERE r.user_id = p_user AND r.restriction_type = 'moderation_hold' -- Spec 2 W7c (R-65): a closer look is never shown
                    AND r.lifted_at IS NULL AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()))
      OR EXISTS (SELECT 1 FROM public.enforcement_records AS er -- Spec 2 W7c: a carried hold
                  WHERE er.scope = 'dating' AND er.restriction_type = 'moderation_hold' -- Spec 2 W7c
                    AND er.phone_hmac = public.dating_phone_hmac_for_user(p_user) -- Spec 2 W7c
                    AND (er.effect_until IS NULL OR er.effect_until > now()) AND er.purge_after > now()) -- Spec 2 W7c
      OR EXISTS (SELECT 1 FROM public.account_holds AS h
                  WHERE h.user_id = p_user AND h.kind = 'safety_review' AND h.resolved_at IS NULL) THEN 'hold'
    WHEN EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                  WHERE r.user_id = p_user AND r.restriction_type = 'age_review' AND r.lifted_at IS NULL
                    AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()))
      OR EXISTS (SELECT 1 FROM public.account_holds AS h
                  WHERE h.user_id = p_user AND h.kind = 'age_review' AND h.resolved_at IS NULL) -- Spec 2 W7c
      OR EXISTS (SELECT 1 FROM public.enforcement_records AS er -- Spec 2 W7c: a carried age check
                  WHERE er.scope = 'dating' AND er.restriction_type = 'age_review' -- Spec 2 W7c
                    AND er.phone_hmac = public.dating_phone_hmac_for_user(p_user) -- Spec 2 W7c
                    AND (er.effect_until IS NULL OR er.effect_until > now()) AND er.purge_after > now()) THEN 'age_review' -- Spec 2 W7c
    ELSE 'unavailable'
  END;
$function$;

CREATE OR REPLACE FUNCTION public.report_dating_introduction(p_idempotency_key text, p_introduction_id uuid, p_category text, p_details text, p_also_block boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_details constant text := NULLIF(btrim(coalesce(p_details, '')), '');
  v_other uuid;
  v_locked uuid;
  v_hmac text;
  v_report uuid;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_introduction_id IS NULL OR NOT private.dating_key_ok(p_idempotency_key) OR private.dating_report_priority(p_category) IS NULL
     OR coalesce(char_length(v_details), 0) > 500 OR p_also_block IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      -- Fix round 2 (N-1): the other person from the card without a lock,
      -- then both setup locks.
      SELECT CASE WHEN i.user_low_id = v_user THEN i.user_high_id ELSE i.user_low_id END INTO v_other
        FROM public.dating_introductions AS i WHERE i.id = p_introduction_id AND v_user IN (i.user_low_id, i.user_high_id)
         -- Task 2 (N2-1): only a report that can file takes the target's lock.
         AND (i.state IN ('generated', 'presented', 'interested') OR i.expires_at > now() - interval '30 days')
         AND NOT private.dating_report_limited(v_user);
      v_locked := v_other; -- Task 2 (N2-1)
      PERFORM private.dating_lock_setup_pair(v_user, v_other);
      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k
                  WHERE k.user_id = v_user AND k.operation = 'report_dating_introduction' AND k.idempotency_key = p_idempotency_key) THEN
        SELECT r.id INTO v_report FROM public.dating_reports AS r
         WHERE r.reporter_user_id = v_user AND r.request_key = 'card:' || p_idempotency_key;
        RETURN coalesce(private.dating_report_reply(v_report, p_also_block), pg_catalog.jsonb_build_object('ok', true));
      END IF;
      SELECT CASE WHEN i.user_low_id = v_user THEN i.user_high_id ELSE i.user_low_id END INTO v_other
        FROM public.dating_introductions AS i
       WHERE i.id = p_introduction_id AND v_user IN (i.user_low_id, i.user_high_id)
         AND (i.state IN ('generated', 'presented', 'interested') -- fix round 1 (M-8): on Today, or within 30 days of its end
              OR i.expires_at > now() - interval '30 days');
      IF NOT FOUND OR v_other IS NULL THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'report_unavailable');
      END IF;
      v_hmac := public.dating_phone_hmac_for_user(v_other);
      BEGIN -- Task 2 fix round 1 (M-6): before the target's report lock
        PERFORM public.check_dating_rate_limit('report', 10, interval '1 day');
      EXCEPTION WHEN invalid_parameter_value THEN
        IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN
          RAISE;
        END IF;
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END;
      IF v_locked IS DISTINCT FROM v_other THEN -- Task 2 (N2-1): as the match's
        RAISE EXCEPTION 'dating:report_relock' USING ERRCODE = 'serialization_failure';
      END IF;
      PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_report_target'),
                                               pg_catalog.hashtext(coalesce(v_hmac, v_other::text)));
      PERFORM public.claim_dating_idempotency('report_dating_introduction', p_idempotency_key);
      v_report := private.dating_file_report(v_user, v_other, v_hmac, NULL, p_introduction_id, p_category, v_details, NULL,
                                             'card:' || p_idempotency_key);
      IF p_also_block THEN
        PERFORM public.block_dating_introduction(p_idempotency_key, p_introduction_id);
      END IF; -- Spec 2 W7c (W7 T3 re-review): a P0 card goes, the pair marked, whatever the block did
      IF private.dating_report_priority(p_category) = 'P0' THEN -- Spec 2 W7c
        UPDATE public.dating_introductions AS i SET state = 'invalidated'
         WHERE i.id = p_introduction_id AND i.state IN ('generated', 'presented', 'interested');
        PERFORM private.dating_mark_pair(v_user, v_other);
      END IF;
      RETURN private.dating_report_reply(v_report, p_also_block); -- fix round 1 (M-1)
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF SQLERRM = 'dating:report_relock' THEN -- Task 2 fix round 1 (M-7): the re-lock is counted
        PERFORM private.bump_metric_internal('dating.report.relock');
      END IF;
      IF v_try = 3 THEN
        PERFORM private.bump_metric_internal('dating.report.busy');
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$function$;

CREATE OR REPLACE FUNCTION public.moderation_audit_log(p_actor uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v_limit constant integer := greatest(1, least(coalesce(p_limit, 100), 500));
  v_seen jsonb := '{}'::jsonb;
  v_out jsonb := '[]'::jsonb;
  v_n integer := 0;
  a public.dating_moderation_actions;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  FOR a IN SELECT x.* FROM public.dating_moderation_actions AS x ORDER BY x.created_at DESC, x.id LOOP
    -- Spec 2 W7c (R-60): the law-enforcement log and the CSAM lift are the safety owner's alone.
    CONTINUE WHEN v_mod.role <> 'safety_owner' AND a.action IN ('law_enforcement_request', 'lift_csam_hold'); -- Spec 2 W7c
    IF a.case_id IS NOT NULL THEN
      IF NOT v_seen ? a.case_id::text THEN
        v_seen := v_seen || pg_catalog.jsonb_build_object(a.case_id::text,
          -- Task 5 (S-5): a routed case's rows are left out for anyone without
          -- routing (decided now, never stored); fix round 1 (I-2): a party's too.
          (v_mod.sensitive_routing_allowed OR NOT coalesce(private.dating_case_needs_sensitive_routing(a.case_id), true))
          AND NOT private.dating_case_party(p_actor, a.case_id));
      END IF;
      CONTINUE WHEN NOT (v_seen ->> a.case_id::text)::boolean;
    END IF;
    v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('id', a.id, 'at', a.created_at,
               'actor', a.actor_id, 'mine', a.actor_id = p_actor, 'action', a.action, 'case_id', a.case_id, 'detail', a.detail));
    v_n := v_n + 1;
    EXIT WHEN v_n >= v_limit;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'actions', v_out);
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_moderation_actions_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.id = OLD.id AND NEW.actor_id = OLD.actor_id AND NEW.action = OLD.action
     AND NEW.detail = OLD.detail AND NEW.created_at = OLD.created_at
     AND (NEW.case_id IS NULL OR NEW.case_id = OLD.case_id)
     AND (NEW.target_user_id IS NULL OR NEW.target_user_id = OLD.target_user_id)
     AND (NEW.case_id IS DISTINCT FROM OLD.case_id OR NEW.target_user_id IS DISTINCT FROM OLD.target_user_id) -- Spec 2 W7c (R-67)
     AND pg_catalog.pg_trigger_depth() > 1 THEN -- Spec 2 W7c: only a foreign key's own SET NULL (a trigger, one level down)
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' AND current_setting('attune.dating_audit_purge', true) = 'on'
     AND OLD.created_at < now() - interval '2 years' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'audit:append_only' USING ERRCODE = '42501';
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_dating_csam_hold(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
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
                        AND r.category = 'csam' -- Spec 2 W7c: a CSAM hold (category csam), not any
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
$function$;

CREATE OR REPLACE FUNCTION public.record_dating_photo_csam(p_photo_id uuid, p_outcome text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
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
                      AND r.category = 'csam' -- Spec 2 W7c: a CSAM hold (category csam), not any
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
$function$;

CREATE OR REPLACE FUNCTION public.record_dating_orphan_scan(p_intent_id uuid, p_outcome text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
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
                      AND r.category = 'csam' -- Spec 2 W7c: a CSAM hold (category csam), not any
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
$function$;

CREATE OR REPLACE FUNCTION private.dating_lift_case_holds(p_case uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  WITH lifted AS ( -- Spec 2 W7c (fix round 1)
  UPDATE public.dating_account_restrictions AS r SET lifted_at = now()
   WHERE r.case_id = p_case AND r.lifted_at IS NULL
     AND r.category IS DISTINCT FROM 'csam' -- Spec 2 W7c (fix round 2): a CSAM hold is the safety owner's lift alone
     AND ((r.restriction_type = 'moderation_hold' AND r.source <> 'csam_hash')
          OR (r.restriction_type = 'age_review' AND r.decided_by IS NULL AND r.source IN ('report', 'carried_over'))) -- Spec 2 W7c (final, I-5): a report's, carried too
    RETURNING r.carried_from) -- Spec 2 W7c
  UPDATE public.enforcement_records AS er SET effect_until = now() -- Spec 2 W7c: a carried hold's record ends with it
    FROM lifted WHERE er.id = lifted.carried_from AND (er.effect_until IS NULL OR er.effect_until > now()); -- Spec 2 W7c
  -- Spec 2 W7c (final, I-5): and every record the case's holds left at a deletion (an
  -- Spec 2 W7c orphaned case closed: its number is not held for 2 years)
  UPDATE public.enforcement_records AS er SET effect_until = now() -- Spec 2 W7c
   WHERE er.case_id = p_case AND er.scope = 'dating' AND er.category IS DISTINCT FROM 'csam' -- Spec 2 W7c
     AND (er.restriction_type = 'moderation_hold' OR (er.restriction_type = 'age_review' AND er.decided_by IS NULL)) -- Spec 2 W7c
     AND (er.effect_until IS NULL OR er.effect_until > now()); -- Spec 2 W7c
$function$;

CREATE OR REPLACE FUNCTION private.dating_restriction_defaults()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF NEW.source IS NULL THEN
    NEW.source := CASE NEW.restriction_type WHEN 'moderation_hold' THEN 'csam_hash'
                                            WHEN 'age_review' THEN 'age_assurance'
                                            ELSE 'moderator' END;
    IF NEW.category IS NULL THEN
      NEW.category := CASE NEW.restriction_type WHEN 'moderation_hold' THEN 'csam'
                                                WHEN 'age_review' THEN 'underage_risk' END;
    END IF;
  END IF;
  -- §6.3: a hold is not appealable until decided, an age review goes
  -- through the ID check, a closer look is never shown; a carried
  -- restriction keeps its one appeal (§6.3), unless it is an age review.
  IF NEW.restriction_type IN ('age_review', 'under_review')
     OR (NEW.restriction_type = 'moderation_hold' AND NEW.source IS DISTINCT FROM 'carried_over') -- Spec 2 W7c
     OR (NEW.restriction_type = 'moderation_hold' AND NEW.category = 'csam') THEN -- Spec 2 W7c (fix round 1, M-11): a carried CSAM hold too
    NEW.appealable := false;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.moderation_lift_hold(p_actor uuid, p_case uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v_n integer;
  v_first jsonb;
  v_rows bigint;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- Task 5 fix round 1 (M-3): a lock not had in 2 s answers busy (counted)
    c := private.dating_case_lock(v_mod, p_case);
    IF c.id IS NULL OR c.target_user_id IS NULL
       OR c.state = 'closed' THEN -- fix round 1 (I-1): a closed case lifts nothing
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    -- Ruling R-56: a hold, or an age check once support has seen the ID.
    -- Fix round 1 (I-1): only what this case placed (never another case's,
    -- which may be one this moderator can't see), never a CSAM hold.
    v_rows := (SELECT count(*) FROM public.dating_account_restrictions AS r WHERE r.case_id = c.id); -- Spec 2 W7c
    -- Spec 2 W7c (final r3): an id_check case's Lift is the ID path while its check is live;
    -- Spec 2 W7c any other decided case offers none (I-7). This moderator's own
    -- Spec 2 W7c lift again is a replay.
    IF c.kind = 'id_check' AND (private.dating_case_id_check(c.id)).id IS NOT NULL THEN -- Spec 2 W7c
      v_n := private.dating_end_id_check(c.id); -- Spec 2 W7c the asked check (a carried one's record too)
      IF c.state IN ('open', 'in_review') THEN -- Spec 2 W7c (owner 2026-11-22): the ID shows an adult: decided,
        PERFORM private.dating_close_case(c.id, p_actor, 'id_verified'); -- Spec 2 W7c its reports not upheld
        PERFORM private.dating_lift_case_holds(c.id); -- Spec 2 W7c (N2-2): as every decision
      END IF; -- Spec 2 W7c: a late ID after No ID came leaves the decided reports as they are (m2-1)
    ELSIF c.kind = 'id_check' OR c.state = 'decided' THEN -- Spec 2 W7c
      SELECT a.detail INTO v_first FROM public.dating_moderation_actions AS a -- Spec 2 W7c
       WHERE a.actor_id = p_actor AND a.case_id = c.id AND a.action = 'lift_hold' AND NOT a.detail ? 'holds' -- Spec 2 W7c
       ORDER BY a.created_at DESC, a.id DESC LIMIT 1; -- Spec 2 W7c
      IF v_first ? 'lifted' AND (v_first ->> 'rows')::bigint IS NOT DISTINCT FROM v_rows THEN -- Spec 2 W7c
        RETURN pg_catalog.jsonb_build_object('ok', true, 'lifted', v_first -> 'lifted'); -- Spec 2 W7c
      END IF; -- Spec 2 W7c
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable'); -- Spec 2 W7c
    ELSE -- Spec 2 W7c: an open case: what it placed, never a CSAM hold
    WITH lifted AS ( -- Spec 2 W7c (fix round 2, N-1)
    UPDATE public.dating_account_restrictions AS r SET lifted_at = now()
     WHERE r.user_id = c.target_user_id AND r.restriction_type IN ('moderation_hold', 'age_review') AND r.lifted_at IS NULL
       AND r.case_id = c.id AND r.source <> 'csam_hash' -- Spec 2 W7c
       AND r.category IS DISTINCT FROM 'csam' -- Spec 2 W7c: a CSAM hold is the safety owner's lift alone
     RETURNING r.carried_from), -- Spec 2 W7c
    ended AS ( -- Spec 2 W7c: a carried hold's or age check's record ends with it
      UPDATE public.enforcement_records AS er SET effect_until = now() -- Spec 2 W7c
        FROM lifted WHERE er.id = lifted.carried_from AND (er.effect_until IS NULL OR er.effect_until > now()) -- Spec 2 W7c
      RETURNING er.id) -- Spec 2 W7c
    SELECT count(*) INTO v_n FROM lifted; -- Spec 2 W7c
    END IF; -- Spec 2 W7c
    IF v_n = 0 THEN
      -- Task 5 (M-11): nothing left to lift after this moderator's own lift,
      -- and nothing placed on the case since (fix round 1, M-6): a replay,
      -- answered with the first count.
      SELECT a.detail INTO v_first FROM public.dating_moderation_actions AS a
       WHERE a.actor_id = p_actor AND a.case_id = c.id AND a.action = 'lift_hold' AND NOT a.detail ? 'holds' -- Spec 2 W7c (r2): not Lift the case's holds
       ORDER BY a.created_at DESC, a.id DESC LIMIT 1;
      IF v_first ? 'lifted' AND (v_first ->> 'rows')::bigint IS NOT DISTINCT FROM v_rows THEN
        RETURN pg_catalog.jsonb_build_object('ok', true, 'lifted', v_first -> 'lifted');
      END IF;
    END IF;
    PERFORM private.dating_audit(p_actor, c.id, 'lift_hold', c.target_user_id,
                                 pg_catalog.jsonb_build_object('lifted', v_n, 'rows', v_rows));
    RETURN pg_catalog.jsonb_build_object('ok', true, 'lifted', v_n);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_place_restriction(p_user uuid, p_type text, p_category text, p_source text, p_case uuid, p_decided_by uuid, p_ends_at timestamp with time zone, p_appealable boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_id uuid;
BEGIN
  -- Fix round 1 (M-11): the person's setup lock, which every CSAM path
  -- holds while it looks for a hold and inserts one: a hit and a report
  -- never both insert.
  PERFORM private.dating_lock_setup(p_user);
  SELECT r.id INTO v_id FROM public.dating_account_restrictions AS r
   WHERE r.user_id = p_user AND r.restriction_type = p_type AND r.lifted_at IS NULL
     AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now())
     AND r.case_id IS NOT DISTINCT FROM p_case -- Spec 2 W7c (final, I-2, I-4): this case's own row only (a replay), never another case's
     AND r.source = p_source -- Spec 2 W7c: placed the same way (never a carried row; a report's never stands for a moderator's)
     AND r.id_check_code IS NULL -- Spec 2 W7c (I-1): never an asked age check
     AND (r.restriction_type <> 'moderation_hold' -- Spec 2 W7c (fix round 3, N2-1): a hold within its class only
          OR coalesce(r.category = 'csam', false) = coalesce(p_category = 'csam', false)) -- Spec 2 W7c
   ORDER BY r.created_at LIMIT 1; -- Spec 2 W7c
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, decided_by,
                                                  ends_at, appealable)
  VALUES (p_user, p_type, p_category, p_source, p_case, p_decided_by, p_ends_at, coalesce(p_appealable, true))
  RETURNING id INTO v_id;
  IF p_source = 'report' AND p_type IN ('moderation_hold', 'age_review') THEN
    PERFORM private.bump_metric_internal('dating.hold.p0');
  END IF;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_close_case(p_case uuid, p_decider uuid, p_outcome text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_state text;
BEGIN
  IF p_outcome IS NULL OR p_outcome NOT IN ('dismissed', 'held', 'restricted', 'asked_for_id', 'no_action', 'orphaned',
                                            'accepted', 'rejected', 'id_verified', 'no_id_received') THEN -- Spec 2 W7c (owner 2026-11-22): the ID shows an adult, or none came
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT c.state INTO v_state FROM public.dating_moderation_cases AS c WHERE c.id = p_case FOR UPDATE;
  IF v_state IS NULL OR v_state NOT IN ('open', 'in_review') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  UPDATE public.dating_moderation_cases AS c
     SET state = CASE WHEN p_outcome IN ('no_action', 'orphaned') THEN 'closed' ELSE 'decided' END,
         decided_at = now(), outcome = p_outcome, assigned_to = coalesce(c.assigned_to, p_decider)
   WHERE c.id = p_case;
  UPDATE public.dating_reports AS r
     SET state = CASE WHEN p_outcome IN ('held', 'restricted', 'asked_for_id', 'no_id_received') THEN 'upheld' -- Spec 2 W7c
                      WHEN p_outcome IN ('dismissed', 'id_verified') THEN 'not_upheld' ELSE 'closed_no_action' END -- Spec 2 W7c
   WHERE r.case_id = p_case AND r.state IN ('open', 'in_review'); -- Spec 2 W7c (final r3): its still-open reports
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.moderation_ask_for_id(p_actor uuid, p_case uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v jsonb;
  v_idc public.dating_moderation_cases; -- Spec 2 W7c
  v_new uuid; -- Spec 2 W7c
  v_hmac text; -- Spec 2 W7c
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- Task 5 fix round 1 (M-3): a lock not had in 2 s answers busy (counted)
    c := private.dating_case_lock(v_mod, p_case);
    IF c.id IS NULL OR c.target_user_id IS NULL OR c.kind IN ('appeal', 'id_check') THEN -- Spec 2 W7c (final r3): never on an ID check
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    -- Spec 2 W7c (final r3): one ID check per person at a time (its case open, or its check
    -- Spec 2 W7c live after No ID came); this moderator's ask from this case again
    -- Spec 2 W7c is a replay.
    v_hmac := coalesce(c.target_phone_hmac, public.dating_phone_hmac_for_user(c.target_user_id)); -- Spec 2 W7c (final r4, m3-2)
    SELECT x.* INTO v_idc FROM public.dating_moderation_cases AS x -- Spec 2 W7c
     WHERE x.kind = 'id_check' -- Spec 2 W7c
       AND (x.target_user_id = c.target_user_id -- Spec 2 W7c: theirs, or an orphaned one on their number
            OR (x.target_user_id IS NULL AND v_hmac IS NOT NULL AND x.target_phone_hmac = v_hmac)) -- Spec 2 W7c (final r4, m3-2)
       AND (x.state IN ('open', 'in_review') OR (private.dating_case_id_check(x.id)).id IS NOT NULL) -- Spec 2 W7c
     ORDER BY x.created_at DESC LIMIT 1; -- Spec 2 W7c
    IF v_idc.id IS NOT NULL THEN -- Spec 2 W7c
      IF v_idc.origin_case_id = c.id AND private.dating_moderation_replayed(p_actor, c.id, 'ask_for_id') THEN -- Spec 2 W7c
        RETURN pg_catalog.jsonb_build_object('ok', true, 'id_case', v_idc.id); -- Spec 2 W7c: a replay
      END IF; -- Spec 2 W7c
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable'); -- Spec 2 W7c
    END IF; -- Spec 2 W7c
    IF c.state NOT IN ('open', 'in_review') THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    -- Spec 2 W7c (final r3): the ID check's own case: kind id_check, awaiting the ID (read
    -- Spec 2 W7c awaiting_id), the asker's; no clock (it waits on the person).
    INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, match_id, state, -- Spec 2 W7c
                                                assigned_to, awaiting_id_since, origin_case_id, sla_due_at) -- Spec 2 W7c
    VALUES ('id_check', c.priority, c.target_user_id, v_hmac, c.match_id, 'in_review', -- Spec 2 W7c (final r4): the number's code too)
            p_actor, now(), c.id, NULL) -- Spec 2 W7c
    RETURNING id INTO v_new; -- Spec 2 W7c
    INSERT INTO public.dating_case_matches (case_id, match_id) -- Spec 2 W7c: its chats, for parties and routing
    SELECT v_new, l.match_id FROM public.dating_case_matches AS l WHERE l.case_id = c.id ON CONFLICT DO NOTHING; -- Spec 2 W7c
    -- Spec 2 W7c (I-1, M-9): its own age check with its code, first; then the age
    -- Spec 2 W7c reports move to it and the original's interim age checks go.
    UPDATE public.dating_moderation_cases AS x -- Spec 2 W7c
       SET awaiting_id_restriction = private.dating_place_id_check(c.target_user_id, v_new, p_actor) -- Spec 2 W7c
     WHERE x.id = v_new; -- Spec 2 W7c
    UPDATE public.dating_reports AS r SET case_id = v_new -- Spec 2 W7c
     WHERE r.case_id = c.id AND r.category = 'underage_risk' AND r.state IN ('open', 'in_review'); -- Spec 2 W7c
    UPDATE public.dating_moderation_cases AS x -- Spec 2 W7c: the age check's priority
       SET priority = coalesce((SELECT min(r.priority) FROM public.dating_reports AS r WHERE r.case_id = v_new), x.priority) -- Spec 2 W7c
     WHERE x.id = v_new; -- Spec 2 W7c
    WITH lifted AS ( -- Spec 2 W7c
      UPDATE public.dating_account_restrictions AS r SET lifted_at = now() -- Spec 2 W7c
       WHERE r.case_id = c.id AND r.restriction_type = 'age_review' AND r.decided_by IS NULL -- Spec 2 W7c
         AND r.source IN ('report', 'carried_over') AND r.lifted_at IS NULL -- Spec 2 W7c
      RETURNING r.carried_from) -- Spec 2 W7c
    UPDATE public.enforcement_records AS er SET effect_until = now() -- Spec 2 W7c
      FROM lifted WHERE er.id = lifted.carried_from AND (er.effect_until IS NULL OR er.effect_until > now()); -- Spec 2 W7c
    -- Spec 2 W7c The original: decided when nothing else is open (its holds go, as
    -- Spec 2 W7c with every decision), else open at its other reports' priority
    -- Spec 2 W7c and clock, its holds unchanged.
    IF NOT EXISTS (SELECT 1 FROM public.dating_reports AS r WHERE r.case_id = c.id AND r.state IN ('open', 'in_review')) THEN -- Spec 2 W7c
      v := private.dating_close_case(c.id, p_actor, 'asked_for_id'); -- Spec 2 W7c
      PERFORM private.dating_lift_case_holds(c.id); -- Spec 2 W7c
    ELSE -- Spec 2 W7c
      UPDATE public.dating_moderation_cases AS x -- Spec 2 W7c
         SET priority = (SELECT min(r.priority) FROM public.dating_reports AS r WHERE r.case_id = c.id AND r.state IN ('open', 'in_review')), -- Spec 2 W7c
             sla_due_at = coalesce((SELECT min(r.sla_due_at) FROM public.dating_reports AS r -- Spec 2 W7c
                                     WHERE r.case_id = c.id AND r.state IN ('open', 'in_review')), x.sla_due_at), -- Spec 2 W7c
             state = 'in_review', assigned_to = coalesce(x.assigned_to, p_actor) -- Spec 2 W7c
       WHERE x.id = c.id; -- Spec 2 W7c
    END IF; -- Spec 2 W7c
    PERFORM private.dating_audit(p_actor, c.id, 'ask_for_id', c.target_user_id, pg_catalog.jsonb_build_object('id_case', v_new)); -- Spec 2 W7c
    PERFORM private.dating_audit(p_actor, v_new, 'ask_for_id', c.target_user_id, pg_catalog.jsonb_build_object('from_case', c.id)); -- Spec 2 W7c
    RETURN pg_catalog.jsonb_build_object('ok', true, 'id_case', v_new); -- Spec 2 W7c
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.moderation_confirm_minor(p_actor uuid, p_case uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- Task 5 fix round 1 (M-3): a lock not had in 2 s answers busy (counted)
    c := private.dating_case_lock(v_mod, p_case);
    IF c.id IS NOT NULL AND c.outcome = 'restricted' AND private.dating_moderation_replayed(p_actor, c.id, 'confirm_minor') THEN
      RETURN pg_catalog.jsonb_build_object('ok', true); -- Task 5 (M-11): a replay
    END IF;
    IF c.id IS NULL OR c.target_user_id IS NULL OR c.kind = 'appeal' -- Spec 2 W7c
       OR NOT (CASE WHEN c.kind = 'id_check' -- Spec 2 W7c (final r3): an ID check open, or its check live (No ID came)
                    THEN c.state IN ('open', 'in_review') OR (private.dating_case_id_check(c.id)).id IS NOT NULL -- Spec 2 W7c
                    ELSE c.state IN ('open', 'in_review') -- Spec 2 W7c
                         AND EXISTS (SELECT 1 FROM public.dating_reports AS r WHERE r.case_id = c.id AND r.category = 'underage_risk') END) THEN -- Spec 2 W7c
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    IF c.state IN ('open', 'in_review') THEN -- Spec 2 W7c
      v := private.dating_close_case(c.id, p_actor, 'restricted'); -- Spec 2 W7c
      IF NOT (v ->> 'ok')::boolean THEN -- Spec 2 W7c
        RETURN v; -- Spec 2 W7c
      END IF; -- Spec 2 W7c
    ELSE -- Spec 2 W7c (m2-2): decided while the check waited: now a confirmed minor
      UPDATE public.dating_moderation_cases AS x SET outcome = 'restricted' WHERE x.id = c.id; -- Spec 2 W7c
    END IF; -- Spec 2 W7c
    PERFORM private.dating_place_restriction(c.target_user_id, 'age_review', 'underage_risk', 'moderator', c.id, p_actor, -- Spec 2 W7c (M-9): first
                                             NULL, false); -- Spec 2 W7c
    PERFORM private.dating_lift_case_holds(c.id); -- fix round 1 (C-1): the case's interim holds go with it
    PERFORM private.dating_end_id_check(c.id); -- Spec 2 W7c (I-1): the asked check gives way to the decision
    UPDATE public.dating_moderation_cases AS x SET awaiting_id_restriction = NULL, awaiting_id_since = NULL -- Spec 2 W7c: no ID action
     WHERE x.id = c.id; -- Spec 2 W7c survives it
    PERFORM public.place_account_hold(c.target_user_id, 'age_review', c.id::text);
    PERFORM private.dating_audit(p_actor, c.id, 'confirm_minor', c.target_user_id);
    RETURN pg_catalog.jsonb_build_object('ok', true);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.moderation_dismiss(p_actor uuid, p_case uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- Task 5 fix round 1 (M-3): a lock not had in 2 s answers busy (counted)
    c := private.dating_case_lock(v_mod, p_case);
    IF c.id IS NULL OR c.kind = 'appeal' -- Spec 2 W7c
       OR (c.kind = 'id_check' AND c.target_user_id IS NULL) THEN -- Spec 2 W7c (final r4, N3-1): an orphaned ID check closes with No ID came only
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    IF c.outcome = 'dismissed' AND private.dating_moderation_replayed(p_actor, c.id, 'dismiss') THEN
      RETURN pg_catalog.jsonb_build_object('ok', true); -- Task 5 (M-11): a replay
    END IF;
    v := private.dating_close_case(c.id, p_actor, 'dismissed');
    IF (v ->> 'ok')::boolean THEN
      PERFORM private.dating_lift_case_holds(c.id);
      IF c.kind = 'id_check' THEN -- Spec 2 W7c (final r3): asked by mistake: the check ends
        PERFORM private.dating_end_id_check(c.id); -- Spec 2 W7c
      END IF; -- Spec 2 W7c
      PERFORM private.dating_audit(p_actor, c.id, 'dismiss', c.target_user_id);
    END IF;
    RETURN v;
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.moderation_case(p_actor uuid, p_case uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v_hmac text;
  v_profile jsonb;
  v_appeal jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  c := private.dating_case_for(v_mod, p_case);
  IF c.id IS NULL THEN
    IF private.dating_case_party(p_actor, p_case) THEN
      PERFORM private.bump_metric_internal('dating.moderation.party_refused'); -- Task 5 fix round 1 (I-2)
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
  END IF;
  v_hmac := coalesce(c.target_phone_hmac, public.dating_phone_hmac_for_user(c.target_user_id));
  SELECT pg_catalog.jsonb_build_object(
           'display_name', p.display_name, 'age', public.account_age(p.user_id),
           'country', p.country_code, 'region', p.region_code,
           'prompts', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('prompt', q.prompt_id, 'answer', q.answer)
                                         ORDER BY q.position)
                                  FROM public.dating_prompts AS q WHERE q.user_id = p.user_id AND q.moderation_state = 'approved'),
                               '[]'::jsonb),
           'photos', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('position', f.position, 'key', f.storage_key)
                                        ORDER BY f.position)
                                 FROM public.dating_profile_photos AS f
                                WHERE f.user_id = p.user_id AND f.moderation_state = 'approved' AND f.csam_state = 'clear'),
                              '[]'::jsonb))
    INTO v_profile
    FROM public.dating_profiles AS p WHERE p.user_id = c.target_user_id;
  IF c.kind = 'appeal' THEN
    SELECT pg_catalog.jsonb_build_object('text', a.text, 'submitted_at', a.submitted_at, 'state', a.state,
             'restriction', pg_catalog.jsonb_build_object('type', r.restriction_type, 'category', r.category,
                              'source', r.source, 'ends_at', r.ends_at, 'starts_at', r.starts_at,
                              'decided_by_me', r.decided_by = p_actor,
                              -- Task 5 (R1-3): nobody is recorded as deciding it (a carried hold,
                              -- a restriction from before W7): only the safety owner decides
                              -- its appeal, 24 hours after it was sent (decider_unknown).
                              'decider_known', r.decided_by IS NOT NULL))
      INTO v_appeal
      FROM public.dating_appeals AS a JOIN public.dating_account_restrictions AS r ON r.id = a.restriction_id
     WHERE a.id = c.appeal_id;
  END IF;
  PERFORM private.dating_audit(p_actor, c.id, 'open_case', c.target_user_id);
  RETURN pg_catalog.jsonb_build_object('ok', true,
    'case', pg_catalog.jsonb_build_object('id', c.id, 'kind', c.kind, 'priority', c.priority, -- Spec 2 W7c (owner 2026-11-22)
              'state', CASE WHEN private.dating_case_awaiting_id(c.state, c.awaiting_id_since) THEN 'awaiting_id' ELSE c.state END, -- Spec 2 W7c
              'id_check', CASE WHEN c.kind = 'id_check' THEN private.dating_case_id_check_json(c.id) END, -- Spec 2 W7c (final r3)
              'origin_case', c.origin_case_id, -- Spec 2 W7c: the case Ask for ID was used on
              'id_case', (SELECT x.id FROM public.dating_moderation_cases AS x -- Spec 2 W7c: the id_check case it opened
                           WHERE x.origin_case_id = c.id AND x.kind = 'id_check' ORDER BY x.created_at DESC LIMIT 1), -- Spec 2 W7c
              'signal_kind', c.signal_kind, 'sla_due_at', c.sla_due_at, 'created_at', c.created_at,
              'decided_at', c.decided_at, 'outcome', c.outcome, 'mine', c.assigned_to = p_actor,
              'gone', c.target_user_id IS NULL),
    'reports', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                           'id', r.id, 'category', r.category, 'priority', r.priority, 'details', r.details,
                           'created_at', r.created_at, 'state', r.state,
                           -- §6.2: "The reporter's messages in this chat triggered: {family}"
                           'reporter_triggered', r.reporter_tripped_family,
                           'evidence', private.dating_evidence_messages(r.id))
                         ORDER BY r.created_at)
                          FROM public.dating_reports AS r -- Spec 2 W7c
                         WHERE r.case_id = c.id OR (r.id = c.report_id AND r.case_id IS NULL)), '[]'::jsonb), -- Spec 2 W7c (final r3): a moved report is its new case's
    'profile', v_profile,
    -- Task 5 (S-5): without routing, an earlier case carries no id: one that
    -- needs routing would read case_unavailable when opened, and so say
    -- what routing knows. Every earlier case is still listed (the history).
    'prior', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('kind', x.kind,
                         'state', CASE WHEN private.dating_case_awaiting_id(x.state, x.awaiting_id_since) THEN 'awaiting_id' ELSE x.state END, -- Spec 2 W7c
                         'outcome', x.outcome, 'created_at', x.created_at) -- Spec 2 W7c
                         || CASE WHEN v_mod.sensitive_routing_allowed THEN pg_catalog.jsonb_build_object('id', x.id)
                                 ELSE '{}'::jsonb END ORDER BY x.created_at DESC)
                        FROM public.dating_moderation_cases AS x
                       WHERE x.id <> c.id
                         AND ((c.target_user_id IS NOT NULL AND x.target_user_id = c.target_user_id)
                              OR (v_hmac IS NOT NULL AND x.target_phone_hmac = v_hmac))
                         -- Fix round 1 (M-2): an open one routed is left out (it is in no queue
                         -- of theirs, and so would say what routing knows).
                         AND (v_mod.sensitive_routing_allowed OR x.state NOT IN ('open', 'in_review')
                              OR NOT coalesce(private.dating_case_needs_sensitive_routing(x.id), true))), '[]'::jsonb),
    'families', coalesce((SELECT pg_catalog.jsonb_agg(DISTINCT e.family)
                            FROM public.dating_safety_events AS e
                           WHERE e.match_id = c.match_id
                              OR e.match_id IN (SELECT l.match_id FROM public.dating_case_matches AS l WHERE l.case_id = c.id)),
                         '[]'::jsonb),
    'appeal', v_appeal);
END;
$function$;

CREATE OR REPLACE FUNCTION public.dating_moderation_sla_check(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_hook constant text := public.app_setting('moderation_alert_webhook');
  r record;
  v_n integer := 0;
  v_mins integer;
  v_req bigint; -- Spec 2 W7c
  v_bad integer := 0; -- Spec 2 W7c
BEGIN
  -- Spec 2 W7c (final, M-2): pg_net answers later; the last runs' posts the webhook
  -- Spec 2 W7c refused (4xx/5xx, timed out, an error) are counted now.
  BEGIN -- Spec 2 W7c (final r2, m-1): an unreadable answer never stops the run (counted)
  IF pg_catalog.to_regclass('net._http_response') IS NOT NULL THEN -- Spec 2 W7c
    EXECUTE $q$SELECT count(*) FROM private.dating_sla_alert_requests AS q JOIN net._http_response AS h ON h.id = q.request_id -- Spec 2 W7c
                WHERE h.status_code IS NULL OR h.status_code NOT BETWEEN 200 AND 299 OR coalesce(h.timed_out, false) -- Spec 2 W7c
                   OR h.error_msg IS NOT NULL$q$ INTO v_bad; -- Spec 2 W7c
    EXECUTE $q$DELETE FROM private.dating_sla_alert_requests AS q USING net._http_response AS h WHERE h.id = q.request_id$q$; -- Spec 2 W7c
  END IF; -- Spec 2 W7c
  EXCEPTION WHEN OTHERS THEN -- Spec 2 W7c
    v_bad := 0; -- Spec 2 W7c
    PERFORM private.bump_metric_internal('dating.sla.answers_unreadable'); -- Spec 2 W7c
  END; -- Spec 2 W7c
  FOR i IN 1..coalesce(v_bad, 0) LOOP -- Spec 2 W7c
    PERFORM private.bump_metric_internal('dating.sla.alert_rejected'); -- Spec 2 W7c
  END LOOP; -- Spec 2 W7c
  DELETE FROM private.dating_sla_alert_requests AS q WHERE q.sent_at < p_now - interval '1 day'; -- Spec 2 W7c
  FOR r IN
    SELECT c.priority, min(c.created_at) AS oldest
      FROM public.dating_moderation_cases AS c
     WHERE c.state IN ('open', 'in_review') AND c.sla_due_at < p_now
       AND c.kind <> 'id_check' -- Spec 2 W7c (final r3): an ID check waits on the person (it has no clock)
     GROUP BY c.priority ORDER BY c.priority
  LOOP
    IF v_hook IS NULL THEN
      PERFORM private.bump_metric_internal('dating.sla.alert_unconfigured');
      CONTINUE;
    END IF;
    v_mins := greatest(0, floor(extract(epoch FROM p_now - r.oldest) / 60))::int;
    BEGIN
      v_req := net.http_post( -- Spec 2 W7c (M-2): its request id kept
        url := v_hook,
        headers := pg_catalog.jsonb_build_object('Content-Type', 'application/json'),
        body := pg_catalog.jsonb_build_object('text',
          r.priority || ' case waiting ' || (v_mins / 60) || ' h ' || (v_mins % 60) || ' m'));
      INSERT INTO private.dating_sla_alert_requests (request_id) VALUES (v_req) ON CONFLICT (request_id) DO NOTHING; -- Spec 2 W7c
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      PERFORM private.bump_metric_internal('dating.sla.alert_failed');
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('alerts', v_n);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_dating_operational_health()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'dating_enabled',public.dating_flag_enabled('dating_mode_enabled'),
    'candidate_generation_enabled',public.dating_flag_enabled('dating_candidate_generation'),
    'exclusion_key_present',public.app_setting('dating_exclusion_key') IS NOT NULL,
    'relationships_ended_without_exclusion_24h',(
      SELECT count(*) FROM public.relationships r
      WHERE r.status = 'ended'
        AND r.ended_at >= now() - interval '24 hours'
        AND NOT EXISTS (
          SELECT 1 FROM public.dating_former_partner_exclusions e
          WHERE e.relationship_id = r.id
        )
    ),
    'active_algorithm_versions',(SELECT count(*) FROM public.dating_algorithm_configs WHERE state='active'),
    'introductions_config',(private.dating_intro_config()).o_version, -- Spec 2 W5a (§5.5): NULL = generation refuses
    'generation_by_country',(SELECT coalesce(jsonb_object_agg(x.partition_key, jsonb_build_object( -- Spec 2 W5a (§4.4 health v2)
                               'cohort', x.cohort_window, 'state', x.state, 'attempts', x.attempts)), '{}'::jsonb) -- Spec 2 W5a
                             FROM (SELECT DISTINCT ON (r.partition_key) r.partition_key, r.cohort_window, r.state, r.attempts -- Spec 2 W5a
                                     FROM public.dating_generation_runs AS r WHERE r.created_at >= now() - interval '36 hours' -- Spec 2 W5a
                                    ORDER BY r.partition_key, r.created_at DESC) AS x), -- Spec 2 W5a
    'stuck_generation_runs',(SELECT count(*) FROM public.dating_generation_runs WHERE state='processing' AND started_at < now()-interval '30 minutes'),
    'failed_generation_runs_24h',(SELECT count(*) FROM public.dating_generation_runs WHERE state IN ('failed','dead_letter') AND created_at >= now()-interval '24 hours'),
    'expired_open_introductions',(SELECT count(*) FROM public.dating_introductions WHERE state IN ('generated','presented','interested') AND expires_at <= now()),
    'pending_bio_moderation',(SELECT count(*) FROM public.dating_profiles WHERE moderation_state='pending'),
    'pending_photo_moderation',(SELECT count(*) FROM public.dating_profile_photos WHERE moderation_state='pending'),
    'environment',private.attune_environment(), -- Spec 2 W1d
    'field_key_present',private.dating_field_key_present(), -- Spec 2 W1d
    -- Spec 2 W1d (§2.4): nothing can write an RPC's parameters to the log.
    'log_settings_safe',coalesce(current_setting('log_statement', true) IN ('none', 'ddl')
      AND (current_setting('log_min_duration_statement', true) = '-1'
           OR current_setting('log_parameter_max_length', true) = '0')
      AND current_setting('log_parameter_max_length_on_error', true) = '0', false),
    'enabled_countries',to_jsonb(private.dating_open_countries()), -- Spec 2 W1d
    'age_assurance_mode',private.dating_verification_mode(), -- Spec 2 W4a
    'verification_awaiting_review',(SELECT count(*) FROM public.dating_verification_sessions WHERE state='awaiting_review'), -- Spec 2 W4a
    'verification_oldest_waiting_hours',(SELECT floor(extract(epoch FROM now() - min(coalesce(awaiting_since, updated_at))) / 3600)::int -- Spec 2 W4a (fix round 1, M-8)
                                           FROM public.dating_verification_sessions WHERE state='awaiting_review'), -- Spec 2 W4a
    -- Spec 2 W1d (B2 I-5, B5 M-4, B6 M-5): each key set and its stored
    -- Spec 2 W1d fingerprint equal (read only; never the counting mismatch()).
    'exclusion_key_fingerprint_ok',private.dating_exclusion_key_ready(), -- Spec 2 W1d
    'field_key_fingerprint_ok',private.dating_field_key_ready(), -- Spec 2 W1d
    'safety_counters_7d',(SELECT jsonb_object_agg(k.key, coalesce((SELECT sum(c.count) FROM public.metric_counters c -- Spec 2 W1d
                            WHERE c.key = k.key AND c.day >= (now() AT TIME ZONE 'utc')::date - 6), 0)) -- Spec 2 W1d
      FROM unnest(ARRAY['dating.deletion.uncarried', 'dating.exclusion_key.mismatch', 'dating.exclusion_key.unseeded', -- Spec 2 W1d
                        'dating.eligibility.key_not_ready', 'dating.field_key.mismatch', 'dating.field_key.missing', -- Spec 2 W1d
                        'dating.parked_pause.failed', -- Spec 2 W1d (fix round 1, M-5)
                        'dating.path_pause.failed', 'dating.gates.busy', -- Spec 2 W2
                        'dating.gates.failed', 'dating.gentle_wait.undated', -- Spec 2 W2 (Task 3 carry: W2 batch 1 fix round 1, M-4 and M-3)
                        'dating.path_pause.swept', -- Spec 2 W2 (Task 3 fix round 1, I-1)
                        'dating.gentle_wait.seen', 'dating.gentle_wait.account_deleted_7d', -- Spec 2 W2 (migration 3, §6.9)
                        'dating.gentle_wait.clear_busy', 'dating.gentle_wait.seen_skipped', 'dating.home.unreadable_field', -- Spec 2 W2 (migration 3 fix round 1)
                        'dating.kill_switch.pending', 'dating.kill_switch.unreadable', -- Spec 2 W1d (migration 11)
                        'dating.verify.sweep_failed', 'dating.verify.id_review_expired', -- Spec 2 W4a (fix round 1, M-7)
                        'dating.deletion.prepare_carry_failed', 'dating.deletion.late_carry_failed', -- W1 final fix (M-4); -- Spec 2 W5a: and
                        'dating.generation.skipped', 'dating.generation.failed', 'dating.generation.unreadable', -- Spec 2 W5a
                        'dating.generation.busy', -- Spec 2 W5a (Task 2 fix round 2, N-3); -- Spec 2 W5c: and
                        'dating.signal.failed', 'dating.signal.busy', 'dating.fairness.unreadable', -- Spec 2 W5c (fix round 1, I-2, M-1, M-5); -- Spec 2 W5 final: and
                        'dating.digest.push_key_missing', 'dating.digest.failed', -- Spec 2 W5 final (M-5, M-3); Spec 2 W6b: the list goes on
                        'dating.pair_marker.unwritten', 'dating.safety.no_config', 'dating.safety.dead_letter', -- Spec 2 W6b
                        'dating.chat.push_failed', 'dating.chat.push_read', -- Spec 2 W6b (fix round 1, M-11: push_read); Spec 2 W6c: and
                        'dating.purge.retried', -- Spec 2 W6c (Task 8, carry M-6): purge steps retried
                        'dating.mask.failed', -- Spec 2 W6c (final server fix, I-8): the masker's fail-closed fallback; Spec 2 W7a: and
                        'dating.report.evidence_unavailable', 'dating.report.hmac_missing', 'dating.report.busy', -- Spec 2 W7a
                        'dating.carry_over.applied', -- Spec 2 W7a
                        'dating.release.busy', 'dating.release.failed', 'dating.hold.p0', -- Spec 2 W7a
                        'dating.deletion.stamp_failed', -- Spec 2 W7a (Task 2, O-1)
                        'dating.restriction.busy', 'dating.report.relock', -- Spec 2 W7a (Task 2 fix round 1, M-4, M-7)
                        'dating.sla.alert_unconfigured', 'dating.sla.alert_failed', -- Spec 2 W7a: W7b's (Ruling R-57: listed once, here)
                        'dating.moderation.not_moderator', 'dating.moderation.party_refused', 'dating.moderation.busy', -- Spec 2 W7a (W7b Task 5 fix round 1: W7b's too, R-57)
                        'dating.moderation.csam_lift', -- Spec 2 W7a (W7c Task 8: the CSAM hold lift, R-57); Spec 2 W7c: and
                        'dating.moderation.no_id', -- Spec 2 W7c (fix round 5): Close, no ID came
                        'dating.appeal.busy', 'dating.sla.alert_rejected', -- Spec 2 W7c (final, M-1, M-2)
                        'dating.sla.answers_unreadable', -- Spec 2 W7c (final r2, m-1)
                        'dating.carry_over.relink_skipped']) AS k(key)), -- Spec 2 W7c (final r4, m3-2)
    -- Spec 2 W7a (§6.2): open report and appeal cases by priority, past their clock,
    -- Spec 2 W7a and reports about a number with no code (the key was missing).
    'reports_open',(SELECT jsonb_build_object( -- Spec 2 W7a
                      'P0', count(*) FILTER (WHERE c.priority = 'P0'), 'P1', count(*) FILTER (WHERE c.priority = 'P1'), -- Spec 2 W7a
                      'P2', count(*) FILTER (WHERE c.priority = 'P2'), 'P3', count(*) FILTER (WHERE c.priority = 'P3'), -- Spec 2 W7a
                      'past_due', count(*) FILTER (WHERE c.sla_due_at < now())) -- Spec 2 W7a
                    FROM public.dating_moderation_cases AS c -- Spec 2 W7a
                   WHERE c.kind IN ('report', 'appeal') AND c.state IN ('open', 'in_review')), -- Spec 2 W7a
    -- Spec 2 W7c (final r4, m3-4): open ID-check cases and the oldest one's wait in hours
    -- Spec 2 W7c (they wait on the person: never paged, never past due).
    'id_checks_open',(SELECT jsonb_build_object('open', count(*), -- Spec 2 W7c
                         'oldest_hours', coalesce(floor(extract(epoch FROM now() - min(c.created_at)) / 3600)::int, 0)) -- Spec 2 W7c
                        FROM public.dating_moderation_cases AS c -- Spec 2 W7c
                       WHERE c.kind = 'id_check' AND c.state IN ('open', 'in_review')), -- Spec 2 W7c
    'reports_without_hmac_30d',(SELECT count(*) FROM public.dating_reports AS r -- Spec 2 W7a
                                 WHERE r.target_phone_hmac IS NULL AND r.created_at >= now() - interval '30 days'), -- Spec 2 W7a
    -- Spec 2 W6b (chat spec §10): the chat's safety outbox and its events.
    'chat_safety_outbox',(SELECT jsonb_build_object( -- Spec 2 W6b
                            'pending', count(*) FILTER (WHERE o.state = 'pending'), -- Spec 2 W6b
                            'processing', count(*) FILTER (WHERE o.state = 'processing'), -- Spec 2 W6b
                            'dead_letter', (SELECT count(*) FROM public.dating_message_safety_outbox AS x WHERE x.state = 'dead_letter'), -- Spec 2 W6b (fix round 1, M-10)
                            'oldest_pending_seconds', coalesce(floor(extract(epoch FROM now() - min(o.created_at) FILTER (WHERE o.state = 'pending'))), 0)) -- Spec 2 W6b
                          FROM public.dating_message_safety_outbox AS o WHERE o.state IN ('pending', 'processing')), -- Spec 2 W6b (fix round 1, M-10): done rows never read
    'chat_safety_config_active',(SELECT c.version FROM public.dating_safety_configs AS c WHERE c.state = 'active'), -- Spec 2 W6b
    'chat_safety_events_24h',(SELECT coalesce(jsonb_object_agg(x.family, x.n), '{}'::jsonb) FROM ( -- Spec 2 W6b
                                SELECT e.family, count(*) AS n FROM public.dating_safety_events AS e -- Spec 2 W6b
                                 WHERE e.created_at >= now() - interval '24 hours' GROUP BY e.family) AS x), -- Spec 2 W6b
    -- Spec 2 W6c (§4.8): the retention purge's failed steps, per step, 7 days
    'purge_failed_7d',(SELECT coalesce(jsonb_object_agg(x.step, x.n), '{}'::jsonb) FROM ( -- Spec 2 W6c
                         SELECT substr(c.key, char_length('dating.purge.failed.') + 1) AS step, sum(c.count) AS n -- Spec 2 W6c
                           FROM public.metric_counters AS c -- Spec 2 W6c
                          WHERE left(c.key, char_length('dating.purge.failed.')) = 'dating.purge.failed.' -- Spec 2 W6c
                            AND c.day >= (now() AT TIME ZONE 'utc')::date - 6 -- Spec 2 W6c
                          GROUP BY 1) AS x), -- Spec 2 W6c
    -- Spec 2 W5a (Task 2 fix round 2, N-3): people left out over the bound, per country, 7 days
    'generation_truncated_7d',(SELECT coalesce(jsonb_object_agg(x.country, x.n), '{}'::jsonb) FROM ( -- Spec 2 W5a
                                 SELECT substr(c.key, char_length('dating.generation.truncated.') + 1) AS country, sum(c.count) AS n -- Spec 2 W5a
                                   FROM public.metric_counters AS c -- Spec 2 W5a
                                  WHERE left(c.key, char_length('dating.generation.truncated.')) = 'dating.generation.truncated.' -- Spec 2 W5a
                                    AND c.day >= (now() AT TIME ZONE 'utc')::date - 6 -- Spec 2 W5a
                                  GROUP BY 1) AS x), -- Spec 2 W5a
    -- W1 final fix (M-4): app deletions refused for a missing exclusion key
    -- W1 final fix (delete-account records prepare's message) in 7 days.
    'deletions_refused_key_missing_7d',(SELECT count(*) FROM public.account_deletion_requests AS r -- W1 final fix (M-4)
                                         WHERE r.completed_at IS NULL AND r.requested_at >= now() - interval '7 days' -- W1 final fix (M-4)
                                           AND r.failure_reason LIKE '%deletion:enforcement_key_missing%'), -- W1 final fix (M-4)
    -- Spec 2 W1d (fix round 1, I-1): every purge still pending, until a switch clears it.
    'kill_switch_pending',(SELECT coalesce(jsonb_agg(jsonb_build_object('scope', k.scope, 'since', k.first_failed_at, -- Spec 2 W1d
                             'sqlstate', k.last_sqlstate, 'attempts', k.attempts) ORDER BY k.scope), '[]'::jsonb) -- Spec 2 W1d
                           FROM private.dating_kill_switch_pending k) -- Spec 2 W1d
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_my_dating_restriction()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  r public.dating_account_restrictions;
  a public.dating_appeals;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- Fix round 1 (M-4): the carry and the release wait at most 2 s; a read
  -- that can't get its locks answers busy (counted), never an error.
  BEGIN
    PERFORM private.dating_carry_over(v_user);
    PERFORM private.dating_release_suspension(v_user);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.restriction.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
  SELECT * INTO r FROM public.dating_account_restrictions AS x
   WHERE x.user_id = v_user AND x.restriction_type <> 'under_review'
     AND x.lifted_at IS NULL AND x.starts_at <= now() AND (x.ends_at IS NULL OR x.ends_at > now())
   ORDER BY x.id_check_code IS NULL, -- Spec 2 W7c (final r2, m-3; final, I-1): the asked check (with its code) first while live
            CASE WHEN x.restriction_type = 'suspended' AND x.ends_at IS NULL THEN 0 -- Spec 2 W7c
                 WHEN x.restriction_type = 'suspended' THEN 1
                 WHEN x.restriction_type = 'age_review' THEN 2 ELSE 3 END,
            x.ends_at DESC NULLS FIRST, x.created_at DESC
   LIMIT 1;
  IF r.id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'restriction', NULL,
                                         'appeal_accepted', private.dating_appeal_accepted(v_user));
  END IF;
  SELECT * INTO a FROM public.dating_appeals AS x WHERE x.restriction_id = r.id;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'appeal_accepted', private.dating_appeal_accepted(v_user),
    'restriction', pg_catalog.jsonb_build_object(
      'id', r.id,
      'type', CASE r.restriction_type WHEN 'moderation_hold' THEN 'hold' ELSE r.restriction_type END,
      'ends_at', r.ends_at,
      'category', r.category,
      -- Spec 2 W7c (final, client I-3, I-1): where it came from (never who reported or
      -- Spec 2 W7c decided), and the asked check's reference code for the ID email.
      'source', CASE WHEN r.restriction_type = 'moderation_hold' AND r.category = 'csam' THEN 'csam' -- Spec 2 W7c
                     WHEN r.id_check_code IS NOT NULL THEN 'id_check' -- Spec 2 W7c
                     WHEN r.source = 'carried_over' THEN 'carried' -- Spec 2 W7c
                     WHEN r.source = 'report' THEN 'p0_interim' -- Spec 2 W7c
                     WHEN r.source = 'csam_hash' THEN 'csam' -- Spec 2 W7c
                     ELSE r.source END, -- Spec 2 W7c: moderator, age_assurance
      'id_check_code', r.id_check_code, -- Spec 2 W7c
      'can_appeal', r.appealable AND a.id IS NULL,
      'appeal', CASE WHEN a.id IS NULL THEN NULL
                     ELSE pg_catalog.jsonb_build_object('state', a.state, 'submitted_at', a.submitted_at,
                                                        'decided_at', a.decided_at) END));
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_report_answer(p_report uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT pg_catalog.jsonb_build_object('ok', true,
           'review', CASE WHEN private.attune_environment() = 'production' -- Spec 2 W7c (final, I-9): and a named safety owner and moderator
                            AND EXISTS (SELECT 1 FROM public.dating_moderators AS m WHERE m.active AND m.role = 'safety_owner') -- Spec 2 W7c
                            AND EXISTS (SELECT 1 FROM public.dating_moderators AS m WHERE m.active AND m.role = 'moderator') -- Spec 2 W7c
                          THEN 'staffed' ELSE 'testing' END, -- Spec 2 W7c
           'sla_hours', greatest(1, ceil(extract(epoch FROM (r.sla_due_at - r.created_at)) / 3600)::int))
    FROM public.dating_reports AS r WHERE r.id = p_report;
$function$;

CREATE OR REPLACE FUNCTION public.submit_dating_appeal(p_idempotency_key text, p_restriction_id uuid, p_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_text constant text := NULLIF(btrim(coalesce(p_text, '')), '');
  r public.dating_account_restrictions;
  v_appeal uuid;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_restriction_id IS NULL OR NOT private.dating_key_ok(p_idempotency_key) OR coalesce(char_length(v_text), 0) > 500 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k
                  WHERE k.user_id = v_user AND k.operation = 'submit_dating_appeal' AND k.idempotency_key = p_idempotency_key) THEN
        RETURN pg_catalog.jsonb_build_object('ok', true);
      END IF;
      SELECT * INTO r FROM public.dating_account_restrictions AS x
       WHERE x.id = p_restriction_id AND x.user_id = v_user
       FOR UPDATE;
      IF r.id IS NULL OR NOT r.appealable OR r.lifted_at IS NOT NULL OR r.starts_at > now()
         OR (r.ends_at IS NOT NULL AND r.ends_at <= now()) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'appeal_unavailable');
      END IF;
      IF EXISTS (SELECT 1 FROM public.dating_appeals AS a WHERE a.restriction_id = r.id) THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'already_appealed');
      END IF;
      PERFORM public.claim_dating_idempotency('submit_dating_appeal', p_idempotency_key);
      INSERT INTO public.dating_appeals (restriction_id, user_id, text) VALUES (r.id, v_user, v_text)
      RETURNING id INTO v_appeal;
      INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, appeal_id, sla_due_at)
      VALUES ('appeal', 'P2', v_user, public.dating_phone_hmac_for_user(v_user), v_appeal, now() + interval '7 days');
      PERFORM private.bump_metric_internal('dating.appeal.submitted');
      RETURN pg_catalog.jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        PERFORM private.bump_metric_internal('dating.appeal.busy'); -- Spec 2 W7c (final, M-1): counted, as the report's
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_release_expired_suspensions()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_user uuid;
  v_n integer := 0;
BEGIN
  FOR v_user IN
    SELECT e.user_id FROM public.dating_enrollments AS e
     WHERE e.state = 'suspended'
       AND NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                        WHERE r.user_id = e.user_id AND r.restriction_type IN ('suspended', 'age_review')
                          AND r.lifted_at IS NULL AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()))
     ORDER BY e.user_id
     LIMIT 500
  LOOP
    BEGIN
      PERFORM 1 FROM public.users AS u WHERE u.id = v_user FOR KEY SHARE SKIP LOCKED;
      IF NOT FOUND THEN
        PERFORM private.bump_metric_internal('dating.release.busy');
        CONTINUE;
      END IF;
      IF NOT pg_catalog.pg_try_advisory_lock(pg_catalog.hashtext('dating_setup'), pg_catalog.hashtext(v_user::text)) THEN -- Spec 2 W7c (final, M-3)
        PERFORM private.bump_metric_internal('dating.release.busy'); -- Spec 2 W7c: a writer of theirs is mid-way: next run
        CONTINUE; -- Spec 2 W7c
      END IF; -- Spec 2 W7c
      BEGIN -- Spec 2 W7c
        IF private.dating_release_suspension(v_user) THEN -- Spec 2 W7c
          v_n := v_n + 1; -- Spec 2 W7c
        END IF; -- Spec 2 W7c
      EXCEPTION WHEN OTHERS THEN -- Spec 2 W7c
        PERFORM pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('dating_setup'), pg_catalog.hashtext(v_user::text)); -- Spec 2 W7c
        RAISE; -- Spec 2 W7c
      END; -- Spec 2 W7c
      PERFORM pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('dating_setup'), pg_catalog.hashtext(v_user::text)); -- Spec 2 W7c
    EXCEPTION WHEN OTHERS THEN
      PERFORM private.bump_metric_internal('dating.release.failed');
    END;
  END LOOP;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_snapshot_evidence(p_report uuid, p_match uuid, p_reporter_side text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_json jsonb;
  v_n integer;
  v_enc bytea;
BEGIN
  IF p_match IS NULL THEN
    RETURN 0;
  END IF;
  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'from', CASE WHEN x.sender_side = p_reporter_side THEN 'reporter' ELSE 'reported' END,
           'kind', x.kind, 'at', x.created_at, 'text', x.body) ORDER BY x.created_at, x.id), '[]'::jsonb),
         count(*)::int
    INTO v_json, v_n
    FROM (SELECT d.id, d.sender_side, d.kind, d.created_at, d.body FROM public.dating_messages AS d
           WHERE d.match_id = p_match ORDER BY d.created_at DESC, d.id DESC LIMIT 50) AS x;
  BEGIN
    v_enc := private.dating_field_encrypt(pg_catalog.jsonb_build_object('v', 1, 'messages', v_json));
  EXCEPTION WHEN OTHERS THEN -- Spec 2 W7c (final, M-6): any failure, not only a missing key: the report stands
    PERFORM private.bump_metric_internal('dating.report.evidence_unavailable');
    RETURN -1;
  END;
  INSERT INTO public.dating_report_evidence (report_id, snapshot_enc, message_count)
  VALUES (p_report, v_enc, v_n)
  ON CONFLICT (report_id) DO NOTHING;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_carry_over(p_user uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_hmac text;
  v_n integer;
  v_case uuid; -- Spec 2 W7c
BEGIN
  IF p_user IS NULL OR EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user AND u.phone_released_at IS NOT NULL) THEN
    RETURN 0;
  END IF;
  v_hmac := public.dating_phone_hmac_for_user(p_user);
  IF v_hmac IS NULL THEN
    RETURN 0;
  END IF;
  -- Task 2: a record to carry takes the person's setup lock before the rows
  -- its restriction changes (the hold writer's order, W7a Task 1 M-11);
  -- a read with nothing (left) to carry takes none (fix round 1, M-3).
  IF NOT EXISTS (SELECT 1 FROM public.enforcement_records AS er
                  WHERE er.scope = 'dating' AND er.phone_hmac = v_hmac AND er.purge_after > now()
                    AND (er.effect_until IS NULL OR er.effect_until > now())
                    AND er.restriction_type IN ('suspended', 'under_review', 'age_review', 'moderation_hold')
                    AND NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS y
                                     WHERE y.user_id = p_user AND y.carried_from = er.id)) -- Spec 2 W7c
     AND NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c -- Spec 2 W7c (final, M-8): or a case to relink
                      WHERE c.target_user_id IS NULL AND c.target_phone_hmac = v_hmac -- Spec 2 W7c
                        AND (c.state IN ('open', 'in_review') OR c.awaiting_id_restriction IS NOT NULL)) THEN -- Spec 2 W7c
    RETURN 0;
  END IF;
  PERFORM private.dating_lock_setup(p_user);
  -- Spec 2 W7c (final, I-5): the number's report-target lock before the records are
  -- Spec 2 W7c read: a console write on its target-less case (dismissing it, which
  -- Spec 2 W7c ends its records) and this carry never miss each other.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_report_target'), pg_catalog.hashtext(v_hmac)); -- Spec 2 W7c
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, ends_at,
                                                  appealable, carried_from, decided_by, id_check_code) -- Spec 2 W7c
  SELECT p_user, er.restriction_type, er.category, 'carried_over',
         (SELECT c.id FROM public.dating_moderation_cases AS c WHERE c.id = er.case_id),
         er.effect_until, er.restriction_type <> 'age_review', er.id,
         er.decided_by, -- fix round 1 (I-1): the decider stays the decider; Spec 2 W7c
         CASE WHEN EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c -- Spec 2 W7c (final, I-1): an asked check, a new code
                            WHERE c.id = er.case_id AND c.awaiting_id_restriction = er.source_restriction_id) -- Spec 2 W7c
              THEN private.dating_id_check_code() END -- Spec 2 W7c
    FROM public.enforcement_records AS er
   WHERE er.scope = 'dating' AND er.phone_hmac = v_hmac
     AND (er.effect_until IS NULL OR er.effect_until > now()) AND er.purge_after > now()
     AND er.restriction_type IN ('suspended', 'under_review', 'age_review', 'moderation_hold')
     AND NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS x
                      WHERE x.user_id = p_user AND x.carried_from = er.id)
  ON CONFLICT (user_id, carried_from) WHERE carried_from IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  -- Fix round 1 (M-1): an appeal already rejected comes with it (no text).
  INSERT INTO public.dating_appeals (restriction_id, user_id, text, submitted_at, state, decided_by, decided_at)
  SELECT x.id, p_user, NULL, er.appeal_submitted_at, 'rejected', er.appeal_decided_by, er.appeal_decided_at
    FROM public.dating_account_restrictions AS x
    JOIN public.enforcement_records AS er ON er.id = x.carried_from
   WHERE x.user_id = p_user AND er.appeal_decided_at IS NOT NULL
  ON CONFLICT (restriction_id) DO NOTHING;
  -- Spec 2 W7c (final, M-8): the number's open cases (and one whose asked check
  -- Spec 2 W7c waits) are this account's again: Hold, Restrict and Ask for ID
  -- Spec 2 W7c reach it; an asked check carried back is its case's check again.
  FOR v_case IN -- Spec 2 W7c (final r4, m3-2): one by one; a clash with the account's own open case is skipped
    SELECT c.id FROM public.dating_moderation_cases AS c -- Spec 2 W7c
     WHERE c.target_user_id IS NULL AND c.target_phone_hmac = v_hmac -- Spec 2 W7c
       AND (c.state IN ('open', 'in_review') OR c.awaiting_id_restriction IS NOT NULL) -- Spec 2 W7c
     ORDER BY c.created_at, c.id -- Spec 2 W7c
  LOOP -- Spec 2 W7c
    BEGIN -- Spec 2 W7c
      UPDATE public.dating_moderation_cases AS c SET target_user_id = p_user WHERE c.id = v_case; -- Spec 2 W7c
    EXCEPTION WHEN unique_violation THEN -- Spec 2 W7c
      PERFORM private.bump_metric_internal('dating.carry_over.relink_skipped'); -- Spec 2 W7c
    END; -- Spec 2 W7c
  END LOOP; -- Spec 2 W7c
  UPDATE public.dating_moderation_cases AS c SET awaiting_id_restriction = x.id -- Spec 2 W7c
    FROM public.dating_account_restrictions AS x JOIN public.enforcement_records AS er ON er.id = x.carried_from -- Spec 2 W7c
   WHERE x.user_id = p_user AND x.case_id = c.id AND er.source_restriction_id = c.awaiting_id_restriction -- Spec 2 W7c
     AND c.target_user_id = p_user; -- Spec 2 W7c (final r4, m3-2): only on a case relinked to this account
  IF v_n > 0 THEN
    PERFORM private.bump_metric_internal('dating.carry_over.applied');
  END IF;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_generation_removed(p_user uuid, p_at timestamp with time zone, p_cfg jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT (private.dating_throttled(p_user) -- Spec 2 W7a: (the dragnet throttle's rule)
     AND (SELECT count(*) FROM public.dating_introductions AS i
           WHERE p_user IN (i.user_low_id, i.user_high_id)
             AND i.created_at > p_at - interval '20 hours' AND i.created_at <= p_at)
         >= coalesce((p_cfg #>> '{dragnet,throttled_daily_max}')::int, 1)) -- Spec 2 W7a
     OR private.dating_report_excluded(p_user) -- Spec 2 W7a (§6.2): an open P0/P1 report case
     OR EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r -- Spec 2 W7a (§6.3): a closer look
                 WHERE r.user_id = p_user AND r.restriction_type = 'under_review' AND r.lifted_at IS NULL -- Spec 2 W7a
                   AND r.starts_at <= p_at AND (r.ends_at IS NULL OR r.ends_at > p_at)) -- Spec 2 W7a; Spec 2 W7c: or
     OR private.dating_closer_look_carried(p_user, p_at); -- Spec 2 W7c (final, I-6): one a deletion left on the number
$function$;

CREATE OR REPLACE FUNCTION private.dating_case_lock(p_mod dating_moderators, p_case uuid)
 RETURNS dating_moderation_cases
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  c public.dating_moderation_cases := private.dating_case_for(p_mod, p_case);
  v_was uuid; -- Spec 2 W7c
BEGIN
  IF c.id IS NOT NULL THEN
    IF c.target_user_id IS NOT NULL THEN
      PERFORM private.dating_lock_setup(c.target_user_id);
    ELSIF c.target_phone_hmac IS NOT NULL THEN -- Spec 2 W7c (final, I-5): no account: the number's report-target lock
      PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_report_target'), -- Spec 2 W7c
                                               pg_catalog.hashtext(c.target_phone_hmac)); -- Spec 2 W7c
    END IF;
    v_was := c.target_user_id; -- Spec 2 W7c
    SELECT x.* INTO c FROM public.dating_moderation_cases AS x WHERE x.id = c.id FOR UPDATE;
    IF v_was IS NULL AND c.target_user_id IS NOT NULL THEN -- Spec 2 W7c: the number came back while this waited:
      RAISE EXCEPTION 'dating:case_relinked' USING ERRCODE = 'lock_not_available'; -- Spec 2 W7c busy (again, with its setup lock)
    END IF; -- Spec 2 W7c
    -- Fix round 1 (M-1): asked again under the lock (a report that landed
    -- while this waited can route the case, or name this moderator).
    IF c.id IS NOT NULL AND (private.dating_case_for(p_mod, c.id)).id IS NULL THEN
      c := NULL;
    END IF;
  END IF;
  IF c.id IS NULL AND private.dating_case_party(p_mod.user_id, p_case) THEN
    PERFORM private.bump_metric_internal('dating.moderation.party_refused'); -- fix round 1 (I-2)
  END IF;
  RETURN c;
END;
$function$;

CREATE OR REPLACE FUNCTION public.moderation_place_hold(p_actor uuid, p_case uuid, p_category text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- Task 5 fix round 1 (M-3): a lock not had in 2 s answers busy (counted)
    IF private.dating_report_priority(p_category) IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
    END IF;
    c := private.dating_case_lock(v_mod, p_case);
    IF c.id IS NULL OR c.state NOT IN ('open', 'in_review') OR c.target_user_id IS NULL
       OR c.kind IN ('appeal', 'id_check') THEN -- fix round 1 (M-4): an appeal case holds nobody; Spec 2 W7c (final r3): nor an ID check
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    IF private.dating_moderation_replayed(p_actor, c.id, 'hold', pg_catalog.jsonb_build_object('category', p_category))
       AND EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                    WHERE r.user_id = c.target_user_id AND r.case_id = c.id AND r.restriction_type = 'moderation_hold'
                      AND r.decided_by = p_actor -- fix round 1 (M-6): this moderator's own hold
                      AND r.lifted_at IS NULL AND (r.ends_at IS NULL OR r.ends_at > now())) THEN
      RETURN pg_catalog.jsonb_build_object('ok', true); -- Task 5 (M-11): a replay (the hold is still on)
    END IF;
    PERFORM private.dating_place_restriction(c.target_user_id, 'moderation_hold', p_category, 'moderator', c.id, p_actor,
                                             NULL, false);
    UPDATE public.dating_moderation_cases AS x SET state = 'in_review', assigned_to = coalesce(x.assigned_to, p_actor)
     WHERE x.id = c.id;
    PERFORM private.dating_audit(p_actor, c.id, 'hold', c.target_user_id, pg_catalog.jsonb_build_object('category', p_category));
    RETURN pg_catalog.jsonb_build_object('ok', true);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.moderation_restrict(p_actor uuid, p_case uuid, p_type text, p_ends_at timestamp with time zone, p_category text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v_detail jsonb;
  v jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- Task 5 fix round 1 (M-3): a lock not had in 2 s answers busy (counted)
    IF p_type IS NULL OR p_type NOT IN ('suspended', 'under_review') OR private.dating_report_priority(p_category) IS NULL
       OR (p_ends_at IS NOT NULL AND p_ends_at <= now()) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
    END IF;
    v_detail := pg_catalog.jsonb_build_object('type', p_type, 'ends_at', p_ends_at, 'category', p_category);
    c := private.dating_case_lock(v_mod, p_case);
    IF c.id IS NULL OR c.target_user_id IS NULL OR c.kind IN ('appeal', 'id_check') THEN -- Spec 2 W7c (final r3): not an ID check
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    IF c.outcome = 'restricted' AND private.dating_moderation_replayed(p_actor, c.id, 'restrict', v_detail) THEN
      RETURN pg_catalog.jsonb_build_object('ok', true); -- Task 5 (M-11): a replay
    END IF;
    IF c.state NOT IN ('open', 'in_review') THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    v := private.dating_close_case(c.id, p_actor, 'restricted');
    IF NOT (v ->> 'ok')::boolean THEN
      RETURN v;
    END IF;
    PERFORM private.dating_lift_case_holds(c.id);
    PERFORM private.dating_place_restriction(c.target_user_id, p_type, p_category, 'moderator', c.id, p_actor, p_ends_at,
                                             p_type = 'suspended');
    PERFORM private.dating_audit(p_actor, c.id, 'restrict', c.target_user_id, v_detail);
    RETURN pg_catalog.jsonb_build_object('ok', true);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_case_party(p_mod uuid, p_case uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  c public.dating_moderation_cases;
  v_hmac text;
  v_from uuid;
BEGIN
  IF p_mod IS NULL OR p_case IS NULL THEN
    RETURN false;
  END IF;
  SELECT * INTO c FROM public.dating_moderation_cases AS x WHERE x.id = p_case;
  IF c.id IS NULL THEN
    RETURN false;
  END IF;
  v_hmac := public.dating_phone_hmac_for_user(p_mod);
  IF c.target_user_id = p_mod OR (v_hmac IS NOT NULL AND c.target_phone_hmac = v_hmac) THEN
    RETURN true;
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_reports AS r
              WHERE (r.case_id = c.id OR r.id = c.report_id)
                AND (r.reporter_user_id = p_mod OR (v_hmac IS NOT NULL AND r.reporter_phone_hmac = v_hmac))) THEN
    RETURN true;
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_matches AS m
              WHERE (m.id = c.match_id OR m.id IN (SELECT l.match_id FROM public.dating_case_matches AS l WHERE l.case_id = c.id))
                AND (p_mod IN (m.user_low_id, m.user_high_id)
                     OR (v_hmac IS NOT NULL AND v_hmac IN (m.low_phone_hmac, m.high_phone_hmac)))) THEN
    RETURN true;
  END IF;
  IF c.kind = 'appeal' THEN
    SELECT r.case_id INTO v_from FROM public.dating_appeals AS a
      JOIN public.dating_account_restrictions AS r ON r.id = a.restriction_id
     WHERE a.id = c.appeal_id;
    IF v_from IS NOT NULL AND v_from <> c.id AND private.dating_case_party(p_mod, v_from) THEN
      RETURN true;
    END IF;
  END IF;
  IF c.kind = 'id_check' AND c.origin_case_id IS NOT NULL AND c.origin_case_id <> c.id -- Spec 2 W7c (final r3): a party to the case
     AND private.dating_case_party(p_mod, c.origin_case_id) THEN -- Spec 2 W7c it came from is a party to it
    RETURN true; -- Spec 2 W7c
  END IF; -- Spec 2 W7c
  RETURN false;
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_case_needs_sensitive_routing(p_case uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  c public.dating_moderation_cases;
  v_target text;
  v_other uuid;
  v_from uuid;
BEGIN
  SELECT * INTO c FROM public.dating_moderation_cases AS x WHERE x.id = p_case;
  IF c.id IS NULL THEN
    RETURN true;
  END IF;
  v_target := private.dating_identity_of(c.target_user_id);
  IF v_target IS NULL OR v_target NOT IN ('woman', 'man') THEN
    RETURN true;
  END IF;
  IF c.kind = 'appeal' THEN
    SELECT r.case_id INTO v_from FROM public.dating_appeals AS a
      JOIN public.dating_account_restrictions AS r ON r.id = a.restriction_id
     WHERE a.id = c.appeal_id;
    IF v_from IS NOT NULL AND v_from <> c.id AND private.dating_case_needs_sensitive_routing(v_from) THEN
      RETURN true;
    END IF;
  END IF;
  IF c.kind = 'id_check' AND c.origin_case_id IS NOT NULL AND c.origin_case_id <> c.id -- Spec 2 W7c (final r3): routed as the case
     AND private.dating_case_needs_sensitive_routing(c.origin_case_id) THEN -- Spec 2 W7c it came from
    RETURN true; -- Spec 2 W7c
  END IF; -- Spec 2 W7c
  FOR v_other IN
    SELECT x.u FROM (
      SELECT unnest(ARRAY[m.user_low_id, m.user_high_id]) AS u
        FROM public.dating_matches AS m
       WHERE m.id = c.match_id
          OR m.id IN (SELECT l.match_id FROM public.dating_case_matches AS l WHERE l.case_id = c.id)
      UNION ALL
      SELECT r.reporter_user_id FROM public.dating_reports AS r WHERE r.case_id = c.id OR r.id = c.report_id
    ) AS x
     WHERE x.u IS DISTINCT FROM c.target_user_id
  LOOP
    IF NOT private.dating_pair_is_man_woman(v_target, private.dating_identity_of(v_other)) THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END;
$function$;

-- ---------------------------------------------------------------------
-- 4b. (W7 final server fix, M-5) Pre-W7 open reports get their case.
-- ---------------------------------------------------------------------
SELECT private.dating_backfill_report_cases();
-- ---------------------------------------------------------------------
-- 5. Self-revoke (the W6 final pattern).
-- ---------------------------------------------------------------------
REVOKE ALL ON TABLE public.dating_escalations, public.law_enforcement_requests
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.moderation_record_escalation(uuid, uuid, text, text), public.moderation_le_requests(uuid),
  public.moderation_record_le_request(uuid, uuid, jsonb), private.dating_transparency_summary(date, date),
  public.moderation_transparency_summary(uuid, date, date),
  public.moderation_csam_holds(uuid), public.moderation_lift_csam_hold(uuid, uuid, text),
  private.dating_case_needed(uuid, timestamp with time zone), public.moderation_case_escalations(uuid, uuid),
  private.dating_case_awaiting_id(text, timestamp with time zone), public.moderation_close_no_id(uuid, uuid),
  private.dating_id_check_code(), private.dating_case_id_check(uuid), private.dating_case_id_check_json(uuid),
  private.dating_end_id_check(uuid), private.dating_place_id_check(uuid, uuid, uuid),
  public.moderation_queue(uuid, integer, text), private.dating_backfill_report_cases(),
  private.dating_closer_look_carried(uuid, timestamp with time zone),
  public.moderation_lift_case_holds(uuid, uuid), private.dating_case_id_record_live(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE private.dating_sla_alert_requests FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
