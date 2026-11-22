-- Spec 2 W7a (§3.7, §4.3, §4.8, §4.9 W7a, §4.10, §6.2, §6.3, §7.1): reports,
-- restrictions, appeals.
--   * Reports v2: the 14 categories and priorities of §3.7, the match or
--     introduction, the reporter's number's code (corroboration), the
--     credibility note, the state, the 4/24/48/72-hour clock, the case.
--     report_dating_match and report_dating_introduction v2 (five
--     arguments, fixed answers); submit_dating_report removed (§4.10).
--   * Evidence: the last 50 messages, encrypted with the field key.
--   * Automatic steps (§6.2), never a ban: a P0 report closes the
--     reporter's match; P0 and P1 remove the person from new generation
--     while the case is open; an interim hold only when corroborated (two
--     independent P0 reports, or underage_risk with a tier-3 age_signal:
--     then an age review); a reporter whose own messages tripped
--     sexual_pressure or financial_request takes no automatic step and
--     never counts.
--   * Cases: one open report case per person; every match a case comes
--     from is linked and held from the purge (W6 M-16).
--   * Restrictions v2: category, source, case, decider, appealable; per
--     type (§6.3): a hold keeps matches open, an age review or a
--     suspension closes them, a closer look shows nothing.
--   * The restricted person's read, one appeal, carry-over at
--     re-registration, an ended suspension released to a pause, the
--     decisions W7b's console calls (close a case, decide an appeal).
--   * The purge: reports at 2 years, evidence at the case's close + 180
--     days (§4.8; W6 T8 carry).
-- Nothing here turns a flag on. Grants in
-- 20261121100010_dating_v2_reports_grants.sql; this file revokes what it
-- creates from every API role first (the W6 final pattern).
BEGIN;
SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------------
-- 1. Categories, priorities and the review clock (§3.7, §6.2).
-- ---------------------------------------------------------------------
-- The 14 categories of §3.7 and their priority; NULL is no category.
CREATE OR REPLACE FUNCTION private.dating_report_priority(p_category text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE p_category
    WHEN 'underage_risk' THEN 'P0' WHEN 'csam' THEN 'P0' WHEN 'child_safety' THEN 'P0' WHEN 'threat_to_life' THEN 'P0'
    WHEN 'sextortion' THEN 'P1' WHEN 'romance_scam' THEN 'P1' WHEN 'threats' THEN 'P1' WHEN 'entrapment' THEN 'P1'
    WHEN 'harassment' THEN 'P2' WHEN 'explicit_content' THEN 'P2' WHEN 'impersonation' THEN 'P2'
    WHEN 'hiding_relationship' THEN 'P2'
    WHEN 'spam' THEN 'P3' WHEN 'other' THEN 'P3' END;
$$;

-- §6.2's human targets. P0: four staffed hours (08:00-22:00 GMT, every
-- day), never more than 24 hours; P1 24 h, P2 48 h, P3 72 h (Ruling R-50).
CREATE OR REPLACE FUNCTION private.dating_report_sla_due(p_priority text, p_at timestamptz)
RETURNS timestamptz
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_local timestamp := p_at AT TIME ZONE 'UTC';
  v_day timestamp := date_trunc('day', p_at AT TIME ZONE 'UTC');
  v_due timestamp;
BEGIN
  IF p_at IS NULL THEN
    RETURN NULL;
  END IF;
  CASE p_priority
  WHEN 'P0' THEN
    IF v_local < v_day + interval '8 hours' THEN
      v_due := v_day + interval '12 hours';
    ELSIF v_local < v_day + interval '18 hours' THEN
      v_due := v_local + interval '4 hours';
    ELSIF v_local < v_day + interval '22 hours' THEN
      v_due := v_day + interval '1 day 8 hours' + (interval '4 hours' - (v_day + interval '22 hours' - v_local));
    ELSE
      v_due := v_day + interval '1 day 12 hours';
    END IF;
    RETURN least(v_due AT TIME ZONE 'UTC', p_at + interval '24 hours');
  WHEN 'P1' THEN RETURN p_at + interval '24 hours';
  WHEN 'P2' THEN RETURN p_at + interval '48 hours';
  WHEN 'P3' THEN RETURN p_at + interval '72 hours';
  ELSE RETURN NULL;
  END CASE;
END;
$$;

-- ---------------------------------------------------------------------
-- 2. Reports v2 (§4.3, §6.2): the match or introduction, the priority,
--    the reporter's number's code (corroboration, R-49), credibility, the
--    state and the case. Old v1 categories are mapped (Ruling R-49).
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_reports
  ADD COLUMN IF NOT EXISTS match_id uuid,
  ADD COLUMN IF NOT EXISTS introduction_id uuid,
  ADD COLUMN IF NOT EXISTS reporter_phone_hmac text,
  ADD COLUMN IF NOT EXISTS priority text,
  ADD COLUMN IF NOT EXISTS reporter_tripped_family text,
  ADD COLUMN IF NOT EXISTS counts_for_corroboration boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_step boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS state text NOT NULL DEFAULT 'open',
  ADD COLUMN IF NOT EXISTS sla_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS case_id uuid,
  ADD COLUMN IF NOT EXISTS request_key text;
CREATE UNIQUE INDEX IF NOT EXISTS dating_reports_request_key_idx ON public.dating_reports (reporter_user_id, request_key)
  WHERE request_key IS NOT NULL;
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_category_check;
UPDATE public.dating_reports
   SET category = CASE category WHEN 'safety_concern' THEN 'other' WHEN 'sexual_content' THEN 'explicit_content' END
 WHERE category IN ('safety_concern', 'sexual_content');
-- A row written without them (W1's fixtures, a definer's insert) takes its
-- priority and its clock from its category.
CREATE OR REPLACE FUNCTION private.dating_report_defaults()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  NEW.priority := coalesce(NEW.priority, private.dating_report_priority(NEW.category));
  NEW.sla_due_at := coalesce(NEW.sla_due_at, private.dating_report_sla_due(NEW.priority, coalesce(NEW.created_at, now())));
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS dating_reports_defaults ON public.dating_reports;
CREATE TRIGGER dating_reports_defaults BEFORE INSERT ON public.dating_reports
  FOR EACH ROW EXECUTE FUNCTION private.dating_report_defaults();
UPDATE public.dating_reports SET priority = private.dating_report_priority(category) WHERE priority IS NULL;
UPDATE public.dating_reports SET sla_due_at = private.dating_report_sla_due(priority, created_at) WHERE sla_due_at IS NULL;
ALTER TABLE public.dating_reports ALTER COLUMN priority SET NOT NULL;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_category_check CHECK (category IN (
  'underage_risk', 'csam', 'child_safety', 'threat_to_life', 'sextortion', 'romance_scam', 'threats', 'entrapment',
  'harassment', 'explicit_content', 'impersonation', 'hiding_relationship', 'spam', 'other'));
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_priority_check;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_priority_check CHECK (priority IN ('P0', 'P1', 'P2', 'P3'));
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_state_check;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_state_check
  CHECK (state IN ('open', 'in_review', 'upheld', 'not_upheld', 'closed_no_action'));
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_reporter_phone_hmac_check;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_reporter_phone_hmac_check
  CHECK (reporter_phone_hmac IS NULL OR reporter_phone_hmac ~ '^[0-9a-f]{64}$');
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_tripped_check;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_tripped_check
  CHECK (reporter_tripped_family IS NULL OR reporter_tripped_family IN ('sexual_pressure', 'financial_request'));
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = 'dating_reports_match_id_fkey') THEN
    ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_match_id_fkey
      FOREIGN KEY (match_id) REFERENCES public.dating_matches (id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = 'dating_reports_introduction_id_fkey') THEN
    ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_introduction_id_fkey
      FOREIGN KEY (introduction_id) REFERENCES public.dating_introductions (id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = 'dating_reports_case_id_fkey') THEN
    ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_case_id_fkey
      FOREIGN KEY (case_id) REFERENCES public.dating_moderation_cases (id) ON DELETE SET NULL;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS dating_reports_case_idx ON public.dating_reports (case_id);
CREATE INDEX IF NOT EXISTS dating_reports_target_idx ON public.dating_reports (target_user_id);
CREATE INDEX IF NOT EXISTS dating_reports_target_hmac_idx ON public.dating_reports (target_phone_hmac);
CREATE INDEX IF NOT EXISTS dating_reports_reporter_idx ON public.dating_reports (reporter_user_id, created_at);
CREATE INDEX IF NOT EXISTS dating_reports_created_idx ON public.dating_reports (created_at);

-- Evidence (§6.2): the last 50 messages of the conversation, both sides,
-- encrypted with the field key; kept until the case closes + 180 days, or
-- while an enforcement record from it lasts (§4.8; the purge decides).
CREATE TABLE IF NOT EXISTS public.dating_report_evidence (
  report_id uuid PRIMARY KEY REFERENCES public.dating_reports (id) ON DELETE CASCADE,
  snapshot_enc bytea NOT NULL,
  message_count integer NOT NULL CHECK (message_count BETWEEN 0 AND 50),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.dating_report_evidence ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
-- 3. Cases (§4.3): one open report case per person (by account, or by
--    the number's code once the account is gone); appeals are cases too.
--    Every match a case's evidence comes from is linked (W6 M-16), and
--    the purge's hold reads the link.
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_moderation_cases ADD COLUMN IF NOT EXISTS appeal_id uuid;
CREATE UNIQUE INDEX IF NOT EXISTS dating_moderation_cases_open_report_idx
  ON public.dating_moderation_cases (target_user_id)
  WHERE kind = 'report' AND state IN ('open', 'in_review') AND target_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS dating_moderation_cases_report_hmac_idx
  ON public.dating_moderation_cases (target_phone_hmac) WHERE kind = 'report';
CREATE TABLE IF NOT EXISTS public.dating_case_matches (
  case_id uuid NOT NULL REFERENCES public.dating_moderation_cases (id) ON DELETE CASCADE,
  match_id uuid NOT NULL REFERENCES public.dating_matches (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (case_id, match_id)
);
CREATE INDEX IF NOT EXISTS dating_case_matches_match_idx ON public.dating_case_matches (match_id);
ALTER TABLE public.dating_case_matches ENABLE ROW LEVEL SECURITY;
INSERT INTO public.dating_case_matches (case_id, match_id)
SELECT c.id, c.match_id FROM public.dating_moderation_cases AS c WHERE c.match_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 4. Restrictions v2 (§4.3, §6.3): the category shown, where it came
--    from, its case, who decided, whether it can be appealed, and the
--    record it was carried from. Rows inserted without a source take one
--    from their type (the CSAM paths' holds, W4's age reviews; R-51).
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_account_restrictions
  ADD COLUMN IF NOT EXISTS category text,
  ADD COLUMN IF NOT EXISTS source text,
  ADD COLUMN IF NOT EXISTS case_id uuid,
  ADD COLUMN IF NOT EXISTS decided_by uuid,
  ADD COLUMN IF NOT EXISTS appealable boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS carried_from uuid;
ALTER TABLE public.dating_account_restrictions DROP CONSTRAINT IF EXISTS dating_account_restrictions_category_check;
ALTER TABLE public.dating_account_restrictions ADD CONSTRAINT dating_account_restrictions_category_check
  CHECK (category IS NULL OR category IN (
    'underage_risk', 'csam', 'child_safety', 'threat_to_life', 'sextortion', 'romance_scam', 'threats', 'entrapment',
    'harassment', 'explicit_content', 'impersonation', 'hiding_relationship', 'spam', 'other'));
ALTER TABLE public.dating_account_restrictions DROP CONSTRAINT IF EXISTS dating_account_restrictions_source_check;
ALTER TABLE public.dating_account_restrictions ADD CONSTRAINT dating_account_restrictions_source_check
  CHECK (source IN ('report', 'moderator', 'csam_hash', 'age_assurance', 'carried_over'));
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = 'dating_account_restrictions_case_id_fkey') THEN
    ALTER TABLE public.dating_account_restrictions ADD CONSTRAINT dating_account_restrictions_case_id_fkey
      FOREIGN KEY (case_id) REFERENCES public.dating_moderation_cases (id) ON DELETE SET NULL;
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS dating_account_restrictions_carried_idx
  ON public.dating_account_restrictions (user_id, carried_from) WHERE carried_from IS NOT NULL;

CREATE OR REPLACE FUNCTION private.dating_restriction_defaults()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
     OR (NEW.restriction_type = 'moderation_hold' AND NEW.source IS DISTINCT FROM 'carried_over') THEN
    NEW.appealable := false;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS dating_account_restrictions_defaults ON public.dating_account_restrictions;
CREATE TRIGGER dating_account_restrictions_defaults
  BEFORE INSERT ON public.dating_account_restrictions
  FOR EACH ROW EXECUTE FUNCTION private.dating_restriction_defaults();
UPDATE public.dating_account_restrictions
   SET source = CASE restriction_type WHEN 'moderation_hold' THEN 'csam_hash' WHEN 'age_review' THEN 'age_assurance'
                                      ELSE 'moderator' END,
       category = coalesce(category, CASE restriction_type WHEN 'moderation_hold' THEN 'csam'
                                                           WHEN 'age_review' THEN 'underage_risk' END),
       appealable = restriction_type = 'suspended'
 WHERE source IS NULL;
ALTER TABLE public.dating_account_restrictions ALTER COLUMN source SET NOT NULL;

-- Appeals (§3.7, §6.3): one per restriction, decided by another person.
CREATE TABLE IF NOT EXISTS public.dating_appeals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restriction_id uuid NOT NULL UNIQUE REFERENCES public.dating_account_restrictions (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  text text CHECK (text IS NULL OR char_length(text) BETWEEN 1 AND 500),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  state text NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'accepted', 'rejected')),
  decided_by uuid,
  decided_at timestamptz,
  CHECK ((state = 'open') = (decided_at IS NULL)),
  CHECK ((state = 'open') = (decided_by IS NULL))
);
CREATE INDEX IF NOT EXISTS dating_appeals_user_idx ON public.dating_appeals (user_id, decided_at);
ALTER TABLE public.dating_appeals ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = 'dating_moderation_cases_appeal_id_fkey') THEN
    ALTER TABLE public.dating_moderation_cases ADD CONSTRAINT dating_moderation_cases_appeal_id_fkey
      FOREIGN KEY (appeal_id) REFERENCES public.dating_appeals (id) ON DELETE CASCADE;
  END IF;
END $$;
-- Task 2 fix round 1: the appeal link is checked at commit. An account's
-- deletion both empties its cases' target (SET NULL) and removes its
-- appeals (and so their cases); checked at once, the first can meet a case
-- the second is about to remove (seen when both rows are the same
-- transaction's).
ALTER TABLE public.dating_moderation_cases
  ALTER CONSTRAINT dating_moderation_cases_appeal_id_fkey DEFERRABLE INITIALLY DEFERRED;

-- ---------------------------------------------------------------------
-- 5. Matches and enforcement records (§6.2, §6.3): a match closed by a
--    P0 report says so; each side's number's code is kept on the match
--    when that side's account is deleted, so the other can still report
--    for 30 days (R-52); a carried record names its case.
-- ---------------------------------------------------------------------
ALTER TABLE public.dating_matches
  ADD COLUMN IF NOT EXISTS low_phone_hmac text,
  ADD COLUMN IF NOT EXISTS high_phone_hmac text;
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_phone_hmac_check;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_phone_hmac_check
  CHECK ((low_phone_hmac IS NULL OR low_phone_hmac ~ '^[0-9a-f]{64}$')
         AND (high_phone_hmac IS NULL OR high_phone_hmac ~ '^[0-9a-f]{64}$'));
DO $$
DECLARE
  v_name text;
BEGIN
  SELECT c.conname INTO v_name FROM pg_catalog.pg_constraint AS c
   WHERE c.conrelid = 'public.dating_matches'::regclass AND c.contype = 'c'
     AND pg_catalog.pg_get_constraintdef(c.oid) LIKE '%closed_reason%' AND pg_catalog.pg_get_constraintdef(c.oid) LIKE '%unmatched%';
  IF v_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.dating_matches DROP CONSTRAINT %I', v_name);
  END IF;
END $$;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_closed_reason_check CHECK (closed_reason IS NULL OR closed_reason IN (
  'unmatched', 'blocked', 'closed_kindly', 'exit', 'account_restricted', 'age_review', 'age_verification_invalid',
  'couple_linked', 'other_linked', 'account_deleted', 'reported', 'other'));
ALTER TABLE public.enforcement_records ADD COLUMN IF NOT EXISTS case_id uuid;
-- Task 2 fix round 1 (I-1, M-1): who decided the restriction, and its one
-- appeal if it was already decided against (rejected), travel with the
-- record: carried over, the same person never decides its appeal, and the
-- appeal is not earned again by deleting the account.
ALTER TABLE public.enforcement_records
  ADD COLUMN IF NOT EXISTS decided_by uuid,
  ADD COLUMN IF NOT EXISTS appeal_submitted_at timestamptz,
  ADD COLUMN IF NOT EXISTS appeal_decided_at timestamptz,
  ADD COLUMN IF NOT EXISTS appeal_decided_by uuid;
ALTER TABLE public.enforcement_records DROP CONSTRAINT IF EXISTS enforcement_records_appeal_check;
ALTER TABLE public.enforcement_records ADD CONSTRAINT enforcement_records_appeal_check
  CHECK ((appeal_decided_at IS NULL) = (appeal_decided_by IS NULL)
         AND (appeal_decided_at IS NULL) = (appeal_submitted_at IS NULL));

-- ---------------------------------------------------------------------
-- 6. The report's pieces.
-- ---------------------------------------------------------------------
-- §6.2 credibility: the reporter's own messages to the target in this
-- match tripped sexual_pressure or financial_request (the family only).
CREATE OR REPLACE FUNCTION private.dating_reporter_tripped(p_reporter uuid, p_match uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT min(e.family) FROM public.dating_safety_events AS e
   WHERE p_match IS NOT NULL AND p_reporter IS NOT NULL
     AND e.match_id = p_match AND e.sender_user_id = p_reporter
     AND e.family IN ('sexual_pressure', 'financial_request')
     AND e.dismissed_at IS NULL; -- fix round 1 (M-7): a dismissed event is a false positive
$$;

-- Fix round 1 (I-1, §6.2): the safety worker records the reporter's own
-- trip after the report was filed (its lag). The sender's open reports
-- from that match stop counting and stepping, and carry the family for
-- the moderator's credibility note. A hold already placed stays: the case
-- shows the note and a moderator decides (W7b). The count of reports
-- changed.
CREATE OR REPLACE FUNCTION private.dating_report_retrip(p_sender uuid, p_match uuid, p_family text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_n integer;
BEGIN
  IF p_sender IS NULL OR p_match IS NULL OR p_family IS NULL OR p_family NOT IN ('sexual_pressure', 'financial_request') THEN
    RETURN 0;
  END IF;
  UPDATE public.dating_reports AS r
     SET reporter_tripped_family = coalesce(r.reporter_tripped_family, p_family),
         counts_for_corroboration = false, auto_step = false
   WHERE r.reporter_user_id = p_sender AND r.match_id = p_match AND r.state IN ('open', 'in_review')
     AND (r.counts_for_corroboration OR r.auto_step OR r.reporter_tripped_family IS NULL);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

-- §6.2: removed from new generation while an open report case holds a
-- credible P0 or P1 report about the person (by account or number).
CREATE OR REPLACE FUNCTION private.dating_report_excluded(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_user IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.dating_reports AS r
      JOIN public.dating_moderation_cases AS c ON c.id = r.case_id
     WHERE c.kind = 'report' AND c.state IN ('open', 'in_review')
       AND r.auto_step AND r.priority IN ('P0', 'P1')
       AND (c.target_user_id = p_user
            OR c.target_phone_hmac = public.dating_phone_hmac_for_user(p_user)));
$$;

-- §6.2 evidence: the last 50 messages of the conversation, both sides, as
-- the reporter's and the other person's, encrypted. -1: no field key
-- (counted; the report stands without it).
CREATE OR REPLACE FUNCTION private.dating_snapshot_evidence(p_report uuid, p_match uuid, p_reporter_side text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'dating:field_key_missing' THEN
      RAISE;
    END IF;
    PERFORM private.bump_metric_internal('dating.report.evidence_unavailable');
    RETURN -1;
  END;
  INSERT INTO public.dating_report_evidence (report_id, snapshot_enc, message_count)
  VALUES (p_report, v_enc, v_n)
  ON CONFLICT (report_id) DO NOTHING;
  RETURN v_n;
END;
$$;

-- One open report case per person: the report joins it (its priority and
-- clock the most urgent of its reports), and its match is linked.
CREATE OR REPLACE FUNCTION private.dating_report_case(p_report uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  r public.dating_reports;
  v_case uuid;
BEGIN
  SELECT * INTO r FROM public.dating_reports AS x WHERE x.id = p_report;
  SELECT c.id INTO v_case FROM public.dating_moderation_cases AS c
   WHERE c.kind = 'report' AND c.state IN ('open', 'in_review')
     AND ((r.target_user_id IS NOT NULL AND c.target_user_id = r.target_user_id)
          OR (r.target_phone_hmac IS NOT NULL AND c.target_phone_hmac = r.target_phone_hmac))
   ORDER BY (c.target_user_id = r.target_user_id) DESC NULLS LAST, c.created_at
   LIMIT 1
   FOR UPDATE;
  IF v_case IS NULL THEN
    INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, report_id, match_id, sla_due_at)
    VALUES ('report', r.priority, r.target_user_id, r.target_phone_hmac, r.id, r.match_id, r.sla_due_at)
    RETURNING id INTO v_case;
  ELSE
    UPDATE public.dating_moderation_cases AS c
       SET priority = least(c.priority, r.priority),
           sla_due_at = least(c.sla_due_at, r.sla_due_at),
           target_user_id = coalesce(c.target_user_id, r.target_user_id),
           target_phone_hmac = coalesce(c.target_phone_hmac, r.target_phone_hmac)
     WHERE c.id = v_case;
  END IF;
  UPDATE public.dating_reports AS x SET case_id = v_case WHERE x.id = r.id;
  IF r.match_id IS NOT NULL THEN
    INSERT INTO public.dating_case_matches (case_id, match_id) VALUES (v_case, r.match_id) ON CONFLICT DO NOTHING;
  END IF;
  RETURN v_case;
END;
$$;

-- §6.2 corroboration for an interim hold: another counting P0 report in
-- an open case about the same person, from another account on another
-- number, the two reporters sharing no phone; or, for underage_risk, a
-- tier-3 age_signal the person sent in this match. 'age_review' when
-- both sides are about age, else 'moderation_hold'; NULL: no hold.
CREATE OR REPLACE FUNCTION private.dating_report_corroborated(p_report uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  r public.dating_reports;
  v_other text;
  v_age boolean;
BEGIN
  SELECT * INTO r FROM public.dating_reports AS x WHERE x.id = p_report;
  IF r.id IS NULL OR NOT r.counts_for_corroboration OR r.priority <> 'P0' OR r.target_user_id IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT o.category INTO v_other
    FROM public.dating_reports AS o
    JOIN public.dating_moderation_cases AS c ON c.id = o.case_id
   WHERE c.kind = 'report' AND c.state IN ('open', 'in_review')
     AND o.id <> r.id AND o.counts_for_corroboration AND o.priority = 'P0'
     AND private.dating_reporter_tripped(o.reporter_user_id, o.match_id) IS NULL -- fix round 1 (I-1): judged again, now
     AND (o.target_user_id = r.target_user_id OR o.target_phone_hmac = r.target_phone_hmac)
     AND o.reporter_user_id IS DISTINCT FROM r.reporter_user_id
     AND o.reporter_phone_hmac IS NOT NULL AND r.reporter_phone_hmac IS NOT NULL
     AND o.reporter_phone_hmac <> r.reporter_phone_hmac
     AND NOT EXISTS (SELECT 1 FROM public.dating_trusted_devices AS a
                       JOIN public.dating_trusted_devices AS b ON b.device_hash = a.device_hash
                      WHERE a.user_id = o.reporter_user_id AND b.user_id = r.reporter_user_id)
   ORDER BY (o.category = 'underage_risk') DESC
   LIMIT 1;
  v_age := r.category = 'underage_risk' AND r.match_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.dating_safety_events AS e
     WHERE e.match_id = r.match_id AND e.family = 'age_signal' AND e.sender_user_id = r.target_user_id
       AND e.tier = 3 -- fix round 1 (M-6): §6.2's tier-3 age_signal
       AND e.dismissed_at IS NULL); -- fix round 1 (M-7): never a dismissed one
  IF r.category = 'underage_risk' AND (v_age OR v_other = 'underage_risk') THEN
    RETURN 'age_review';
  END IF;
  RETURN CASE WHEN v_other IS NOT NULL THEN 'moderation_hold' END;
END;
$$;

-- The one writer of a restriction (W7a holds; W7b's console decisions):
-- a live one of the same type is kept, never doubled.
CREATE OR REPLACE FUNCTION private.dating_place_restriction(p_user uuid, p_type text, p_category text, p_source text,
                                                            p_case uuid, p_decided_by uuid, p_ends_at timestamptz,
                                                            p_appealable boolean)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
   ORDER BY r.created_at LIMIT 1;
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
$$;

-- The shared core of both report RPCs (the caller holds the reporter's
-- setup lock and the target's report lock): the report, its evidence, its
-- case, its count, and a corroborated hold. Returns the report's id.
CREATE OR REPLACE FUNCTION private.dating_file_report(p_reporter uuid, p_target uuid, p_target_hmac text, p_match uuid,
                                                      p_intro uuid, p_category text, p_details text, p_reporter_side text,
                                                      p_key text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_priority constant text := private.dating_report_priority(p_category);
  v_tripped constant text := private.dating_reporter_tripped(p_reporter, p_match);
  v_hmac constant text := public.dating_phone_hmac_for_user(p_reporter);
  v_old_enough boolean;
  v_id uuid;
  v_case uuid;
  v_hold text;
BEGIN
  v_old_enough := coalesce((SELECT u.created_at <= now() - interval '72 hours' FROM public.users AS u WHERE u.id = p_reporter), false);
  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, target_phone_hmac, reporter_phone_hmac, category,
                                     details, match_id, introduction_id, priority, reporter_tripped_family,
                                     counts_for_corroboration, auto_step, sla_due_at, request_key)
  VALUES (p_reporter, p_target, p_target_hmac, v_hmac, p_category, p_details, p_match, p_intro, v_priority, v_tripped,
          v_priority = 'P0' AND v_tripped IS NULL AND v_old_enough AND v_hmac IS NOT NULL,
          -- §6.2: P0 and P1 remove from new generation; impersonation and
          -- the other P2/P3 categories take no automatic step.
          v_tripped IS NULL AND v_priority IN ('P0', 'P1'),
          private.dating_report_sla_due(v_priority, now()), p_key)
  RETURNING id INTO v_id;
  IF p_target_hmac IS NULL THEN
    PERFORM private.bump_metric_internal('dating.report.hmac_missing');
  END IF;
  PERFORM private.dating_snapshot_evidence(v_id, p_match, p_reporter_side);
  v_case := private.dating_report_case(v_id);
  PERFORM private.bump_metric_internal('dating.report.' || p_category);
  v_hold := private.dating_report_corroborated(v_id);
  IF v_hold IS NOT NULL THEN
    PERFORM private.dating_place_restriction(p_target, v_hold, p_category, 'report', v_case, NULL, NULL, false);
  END IF;
  RETURN v_id;
END;
$$;

-- What a sent report answers: whether a person reads it yet, and in how
-- many hours at most (from its clock).
CREATE OR REPLACE FUNCTION private.dating_report_answer(p_report uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT pg_catalog.jsonb_build_object('ok', true,
           'review', CASE WHEN private.attune_environment() = 'production' THEN 'staffed' ELSE 'testing' END,
           'sla_hours', greatest(1, ceil(extract(epoch FROM (r.sla_due_at - r.created_at)) / 3600)::int))
    FROM public.dating_reports AS r WHERE r.id = p_report;
$$;

-- Fix round 1 (M-1): the answer, and "blocked": false when the reporter
-- asked to block too and the two are not blocked (by account or number:
-- the block was refused, say for the day's 20, or busy). The same on a
-- replay.
CREATE OR REPLACE FUNCTION private.dating_report_reply(p_report uuid, p_also_block boolean)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.dating_report_answer(r.id)
         || CASE WHEN p_also_block
                      AND NOT ((r.reporter_user_id IS NOT NULL AND r.target_user_id IS NOT NULL
                                AND private.dating_pair_blocked(r.reporter_user_id, r.target_user_id))
                               OR EXISTS (SELECT 1 FROM public.dating_block_hmacs AS k
                                           WHERE k.blocker_hmac = r.reporter_phone_hmac AND k.blocked_hmac = r.target_phone_hmac))
                 THEN pg_catalog.jsonb_build_object('blocked', false) ELSE '{}'::jsonb END
    FROM public.dating_reports AS r WHERE r.id = p_report;
$$;

-- Fix round 1 (M-8): since when the two are blocked (by account or by
-- number), NULL when they aren't: a chat only the block ended is in the
-- ended list, and can be reported, for 30 days from it.
CREATE OR REPLACE FUNCTION private.dating_pair_blocked_since(p_a uuid, p_b uuid)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT least((SELECT min(k.created_at) FROM public.dating_blocks AS k
                 WHERE k.blocker_user_id IN (p_a, p_b) AND k.blocked_user_id IN (p_a, p_b) AND k.blocker_user_id <> k.blocked_user_id),
               (SELECT min(k.created_at) FROM public.dating_block_hmacs AS k
                 CROSS JOIN LATERAL (SELECT public.dating_phone_hmac_for_user(p_a) AS ha, public.dating_phone_hmac_for_user(p_b) AS hb) AS y
                 WHERE (k.blocker_hmac, k.blocked_hmac) IN ((y.ha, y.hb), (y.hb, y.ha))));
$$;

-- A suspension that ended (lifted, or past its date) leaves Dating
-- paused, never suspended for good: the person resumes when ready
-- (R-53). The lift does it at once (the restriction trigger); Task 2's
-- cron does it for one that ran out.
CREATE OR REPLACE FUNCTION private.dating_release_suspension(p_user uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.dating_enrollments AS e
     SET state = 'paused', paused_at = coalesce(e.paused_at, now()), pause_reason = coalesce(e.pause_reason, 'gates'),
         updated_at = now()
   WHERE e.user_id = p_user AND e.state = 'suspended'
     AND NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                      WHERE r.user_id = p_user AND r.restriction_type IN ('suspended', 'age_review')
                        AND r.lifted_at IS NULL AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()));
  RETURN FOUND;
END;
$$;

-- Fix round 2 (N-1): both people's setup locks, in one id order, then
-- both people's same-gender country locks in one sorted batch, before any
-- row. A report that places a hold needs the target's setup lock (the
-- CSAM paths' lock, M-11); taken here first, the target's own Unmatch,
-- Close kindly, Block or exit (setup lock, then the match row) and the
-- kill switch (every country exclusive, sorted, then rows) wait for the
-- report at their first lock and never close a cycle with it.
CREATE OR REPLACE FUNCTION private.dating_lock_setup_pair(p_a uuid, p_b uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_u uuid;
BEGIN
  FOR v_u IN SELECT DISTINCT x.u FROM unnest(ARRAY[p_a, p_b]) AS x(u) WHERE x.u IS NOT NULL ORDER BY 1 LOOP
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_setup'), pg_catalog.hashtext(v_u::text));
  END LOOP;
  PERFORM private.dating_lock_same_gender_all(
    ARRAY(SELECT p.country_code::text FROM public.dating_profiles AS p WHERE p.user_id IN (p_a, p_b))
    || ARRAY(SELECT c::text FROM public.dating_preferences AS d, unnest(d.open_abroad) AS c WHERE d.user_id IN (p_a, p_b)));
END;
$$;

-- Task 2 (N2-1): the reporter has used the day's 10 reports (a read; the
-- count itself is check_dating_rate_limit's, after the locks).
CREATE OR REPLACE FUNCTION private.dating_report_limited(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_rate_limits AS l
                  WHERE l.user_id = p_user AND l.operation = 'report'
                    AND l.window_started_at + interval '1 day' > now() AND l.request_count >= 10);
$$;

-- ---------------------------------------------------------------------
-- 7. The report RPCs v2 (§3.7, §6.2). A safety write: no phone check and
--    no eligibility check (as Block, R-36); only membership. 10 a day.
--    From a match: while it is open, and for 30 days after it ended for
--    any reason (unmatch, block, close, the other's deletion), including
--    a chat only the two numbers' block ended (W6 T2 N-4).
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.report_dating_match(text, uuid, text, text);
DROP FUNCTION IF EXISTS public.report_dating_introduction(text, uuid, text, text);
DROP FUNCTION IF EXISTS public.submit_dating_report(text, uuid, text, text);

CREATE OR REPLACE FUNCTION public.report_dating_match(p_idempotency_key text, p_match_id uuid, p_category text,
                                                      p_details text, p_also_block boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_details constant text := NULLIF(btrim(coalesce(p_details, '')), '');
  v_m public.dating_matches;
  v_other uuid;
  v_locked uuid;
  v_hmac text;
  v_side text;
  v_report uuid;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_match_id IS NULL OR NOT private.dating_key_ok(p_idempotency_key) OR private.dating_report_priority(p_category) IS NULL
     OR coalesce(char_length(v_details), 0) > 500 OR p_also_block IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      -- Fix round 2 (N-1): the other person from the match without a lock
      -- (who is in it never changes but to NULL), then both setup locks.
      SELECT CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END INTO v_other
        FROM public.dating_matches AS m WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id)
         -- Task 2 (N2-1): only a report that can file takes the target's lock (in
         -- its window, within the day's 10, on this read); the rest answer
         -- below, after the reporter's own lock alone, and never make the
         -- target wait. The checks after the locks decide.
         AND (coalesce(m.evidence_until > now(), false)
              OR (m.state = 'active' AND coalesce(private.dating_pair_blocked_since(m.user_low_id, m.user_high_id)
                                                  > now() - interval '30 days', true)))
         AND NOT private.dating_report_limited(v_user);
      v_locked := v_other; -- Task 2 (N2-1)
      PERFORM private.dating_lock_setup_pair(v_user, v_other);
      IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS k
                  WHERE k.user_id = v_user AND k.operation = 'report_dating_match' AND k.idempotency_key = p_idempotency_key) THEN
        SELECT r.id INTO v_report FROM public.dating_reports AS r
         WHERE r.reporter_user_id = v_user AND r.request_key = 'match:' || p_idempotency_key;
        RETURN coalesce(private.dating_report_reply(v_report, p_also_block), pg_catalog.jsonb_build_object('ok', true));
      END IF;
      -- The match without a lock (who is in it never changes but to NULL),
      -- then the target's report lock, then the match row (send's order).
      SELECT * INTO v_m FROM public.dating_matches AS m
       WHERE m.id = p_match_id AND v_user IN (m.user_low_id, m.user_high_id);
      IF NOT FOUND
         OR NOT ((v_m.state = 'active' -- fix round 1 (M-8): a chat only a block ended, for 30 days from the block
                  AND coalesce(private.dating_pair_blocked_since(v_m.user_low_id, v_m.user_high_id) > now() - interval '30 days', true))
                 OR coalesce(v_m.evidence_until > now(), false)) THEN -- fix round 1: NULL never reportable
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'report_unavailable');
      END IF;
      v_side := CASE WHEN v_m.user_low_id = v_user THEN 'low' ELSE 'high' END;
      v_other := CASE WHEN v_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END;
      v_hmac := coalesce(public.dating_phone_hmac_for_user(v_other),
                         CASE WHEN v_side = 'low' THEN v_m.high_phone_hmac ELSE v_m.low_phone_hmac END);
      BEGIN -- Task 2 fix round 1 (M-6): before the target's report lock and the row
        PERFORM public.check_dating_rate_limit('report', 10, interval '1 day');
      EXCEPTION WHEN invalid_parameter_value THEN
        IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN
          RAISE;
        END IF;
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END;
      IF v_locked IS DISTINCT FROM v_other THEN -- Task 2 (N2-1): it can file after all (the window opened or
        RAISE EXCEPTION 'dating:report_relock' USING ERRCODE = 'serialization_failure'; -- the day turned while it
      END IF; -- waited): again from the top, the target's lock first
      PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('dating_report_target'),
                                               pg_catalog.hashtext(coalesce(v_hmac, v_other::text, p_match_id::text)));
      SELECT * INTO v_m FROM public.dating_matches AS m WHERE m.id = p_match_id FOR UPDATE;
      PERFORM public.claim_dating_idempotency('report_dating_match', p_idempotency_key);
      v_report := private.dating_file_report(v_user, v_other, v_hmac, p_match_id, NULL, p_category, v_details, v_side,
                                             'match:' || p_idempotency_key);
      IF p_also_block AND v_other IS NOT NULL THEN
        PERFORM public.block_dating_match(p_idempotency_key, p_match_id);
      ELSIF p_also_block AND v_hmac IS NOT NULL AND public.dating_phone_hmac_for_user(v_user) IS NOT NULL THEN
        -- The other account is gone: the block is kept by number.
        INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac, purge_after)
        VALUES (public.dating_phone_hmac_for_user(v_user), v_hmac, now() + interval '2 years')
        ON CONFLICT (blocker_hmac, blocked_hmac) DO NOTHING;
      END IF;
      -- §6.2 P0: the reporter's match closes (once a report is in, the
      -- pair is never introduced again).
      IF private.dating_report_priority(p_category) = 'P0' AND v_m.state = 'active'
         AND EXISTS (SELECT 1 FROM public.dating_matches AS m WHERE m.id = p_match_id AND m.state = 'active') THEN
        UPDATE public.dating_matches AS m
           SET state = 'closed', closed_reason = 'reported', closed_at = coalesce(m.closed_at, now()),
               evidence_until = now() + interval '30 days'
         WHERE m.id = p_match_id AND m.state = 'active';
        IF v_other IS NOT NULL THEN
          PERFORM private.dating_mark_pair(v_user, v_other);
        END IF;
        PERFORM private.dating_bump_chat(x.u, p_match_id)
           FROM (VALUES (v_user), (v_other)) AS x(u) WHERE x.u IS NOT NULL;
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
$$;

-- From a card on Today (an introduction the reporter is in, any state,
-- while it is on Today and for 30 days after its time there ends; fix
-- round 1, M-8): no evidence (there is no conversation).
CREATE OR REPLACE FUNCTION public.report_dating_introduction(p_idempotency_key text, p_introduction_id uuid,
                                                             p_category text, p_details text,
                                                             p_also_block boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
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
      ELSIF private.dating_report_priority(p_category) = 'P0' THEN
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
$$;

-- ---------------------------------------------------------------------
-- 7b. Closing a case (W7b's console calls it, never a client): it always
--     stamps decided_at (W6 T5: the cleared-signal filter reads it) and
--     settles the case's reports.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_close_case(p_case uuid, p_decider uuid, p_outcome text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_state text;
BEGIN
  IF p_outcome IS NULL OR p_outcome NOT IN ('dismissed', 'held', 'restricted', 'asked_for_id', 'no_action', 'orphaned',
                                            'accepted', 'rejected') THEN
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
     SET state = CASE WHEN p_outcome IN ('held', 'restricted', 'asked_for_id') THEN 'upheld'
                      WHEN p_outcome = 'dismissed' THEN 'not_upheld' ELSE 'closed_no_action' END
   WHERE r.case_id = p_case;
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------
-- 8. Carry-over at re-registration (§6.3): each live Dating enforcement
--    record on this number becomes a restriction of this account, from
--    'carried_over', with its category and its one appeal (an age review
--    goes through the ID check). Never for a parked account (Spec 1 O3,
--    built default no). Idempotent per record. (Fix round 1, I-1, M-1)
--    With its decider (who never decides its appeal), and its appeal if
--    that was already rejected: deleting the account earns no new one.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_carry_over(p_user uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_hmac text;
  v_n integer;
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
                                     WHERE y.user_id = p_user AND y.carried_from = er.id)) THEN
    RETURN 0;
  END IF;
  PERFORM private.dating_lock_setup(p_user);
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, ends_at,
                                                  appealable, carried_from, decided_by)
  SELECT p_user, er.restriction_type, er.category, 'carried_over',
         (SELECT c.id FROM public.dating_moderation_cases AS c WHERE c.id = er.case_id),
         er.effect_until, er.restriction_type <> 'age_review', er.id,
         er.decided_by -- fix round 1 (I-1): the decider stays the decider
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
  IF v_n > 0 THEN
    PERFORM private.bump_metric_internal('dating.carry_over.applied');
  END IF;
  RETURN v_n;
END;
$$;

-- ---------------------------------------------------------------------
-- 9. The cron for a suspension that ran out (the lift's release is in
--    section 6): every 15 minutes, users key-share, skip locked, each
--    person in its own block, counted.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_release_expired_suspensions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
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
      IF private.dating_release_suspension(v_user) THEN
        v_n := v_n + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      PERFORM private.bump_metric_internal('dating.release.failed');
    END;
  END LOOP;
  RETURN v_n;
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = 'cron') THEN
    PERFORM cron.unschedule(j.jobid) FROM cron.job AS j WHERE j.jobname = 'release-dating-suspensions';
    PERFORM cron.schedule('release-dating-suspensions', '*/15 * * * *', $c$SELECT private.dating_release_expired_suspensions()$c$);
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 10. What the restricted person sees (§3.7): the restriction shown
--     first (closed for good, then until a date, then the age check,
--     then a hold; a closer look never), its category, whether it can be
--     appealed, and the appeal's state. Never who reported, what they
--     wrote, the evidence, the case or who decided. A read that writes
--     (the carry-over, a release): VOLATILE. Not phone-checked: a
--     restricted person may not be able to check a new phone (R-54).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_dating_restriction()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
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
   ORDER BY CASE WHEN x.restriction_type = 'suspended' AND x.ends_at IS NULL THEN 0
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
      'can_appeal', r.appealable AND a.id IS NULL,
      'appeal', CASE WHEN a.id IS NULL THEN NULL
                     ELSE pg_catalog.jsonb_build_object('state', a.state, 'submitted_at', a.submitted_at,
                                                        'decided_at', a.decided_at) END));
END;
$$;

-- An appeal of this person's accepted in the last 7 days (§3.7: "Your
-- appeal was accepted. Dating is open again.", on the Dating section).
CREATE OR REPLACE FUNCTION private.dating_appeal_accepted(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_appeals AS a
                  WHERE a.user_id = p_user AND a.state = 'accepted' AND a.decided_at > now() - interval '7 days');
$$;

-- ---------------------------------------------------------------------
-- 11. One appeal (§3.7, §6.3): to a live, appealable restriction of the
--     caller's, once; it opens an appeal case due in 7 days. Not
--     phone-checked (R-54). The text is optional, at most 500 characters.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_dating_appeal(p_idempotency_key text, p_restriction_id uuid, p_text text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
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
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- ---------------------------------------------------------------------
-- 12. The decision W7b's console calls on an appeal (never a client's):
--     decided by someone other than the restriction's decider, or by the
--     safety owner at least 24 hours after the appeal when the owner made
--     the decision (§4.3, §6.3, mutant 15). Accepting lifts the
--     restriction (the lift releases the suspension) and ends a carried
--     record. (Closing a case is Task 1's, section 7b.) Fix round 1: a
--     restriction with no recorded decider counts as the decider's own
--     (only the safety owner, after 24 hours, I-1); the person's setup
--     lock first, as every writer of their restrictions (M-5).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_decide_appeal(p_appeal uuid, p_decider uuid, p_decider_owner boolean,
                                                        p_accept boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  a public.dating_appeals;
  r public.dating_account_restrictions;
  v_case uuid;
  v_country text;
  v_person uuid;
BEGIN
  IF p_appeal IS NULL OR p_decider IS NULL OR p_accept IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT x.user_id INTO v_person FROM public.dating_appeals AS x WHERE x.id = p_appeal; -- fix round 1 (M-5)
  IF v_person IS NOT NULL THEN
    PERFORM private.dating_lock_setup(v_person); -- fix round 1 (M-5): before the rows
  END IF;
  SELECT * INTO a FROM public.dating_appeals AS x WHERE x.id = p_appeal FOR UPDATE;
  IF a.id IS NULL OR a.state <> 'open' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'appeal_unavailable');
  END IF;
  SELECT * INTO r FROM public.dating_account_restrictions AS x WHERE x.id = a.restriction_id FOR UPDATE;
  IF (r.decided_by IS NULL OR r.decided_by = p_decider) -- fix round 1 (I-1): an unknown decider is never "anyone"
     AND NOT (coalesce(p_decider_owner, false) AND now() >= a.submitted_at + interval '24 hours') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'same_decider');
  END IF;
  UPDATE public.dating_appeals AS x
     SET state = CASE WHEN p_accept THEN 'accepted' ELSE 'rejected' END, decided_by = p_decider, decided_at = now()
   WHERE x.id = a.id;
  SELECT c.id INTO v_case FROM public.dating_moderation_cases AS c
   WHERE c.appeal_id = a.id AND c.state IN ('open', 'in_review');
  IF v_case IS NOT NULL THEN
    PERFORM private.dating_close_case(v_case, p_decider, CASE WHEN p_accept THEN 'accepted' ELSE 'rejected' END);
  END IF;
  IF p_accept THEN
    UPDATE public.dating_account_restrictions AS x SET lifted_at = now() WHERE x.id = r.id AND x.lifted_at IS NULL;
    IF r.carried_from IS NOT NULL THEN
      UPDATE public.enforcement_records AS er SET effect_until = now()
       WHERE er.id = r.carried_from AND (er.effect_until IS NULL OR er.effect_until > now());
    END IF;
    UPDATE public.dating_reports AS x SET state = 'not_upheld' WHERE r.case_id IS NOT NULL AND x.case_id = r.case_id;
    SELECT lower(p.country_code::text) INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = a.user_id;
    PERFORM private.bump_metric_internal('dating.appeal.accepted');
    IF v_country ~ '^[a-z]{2}$' THEN
      PERFORM private.bump_metric_internal('dating.overturned.' || v_country);
    END IF;
  ELSE
    PERFORM private.bump_metric_internal('dating.appeal.rejected');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------
-- 13. Functions re-created from their live bodies; only the lines marked
--     "-- Spec 2 W7a" change.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_dating_restriction_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF NEW.lifted_at IS NULL AND NEW.starts_at <= now()
     AND (NEW.ends_at IS NULL OR NEW.ends_at > now()) THEN
   IF NEW.restriction_type IN ('suspended', 'age_review') THEN -- Spec 2 W7a (§6.3): these close every match
    UPDATE public.dating_enrollments SET state='suspended',updated_at=now()
      WHERE user_id=NEW.user_id AND state<>'exited';
    UPDATE public.dating_profiles SET profile_state='paused',updated_at=now()
      WHERE user_id=NEW.user_id AND profile_state='active';
    PERFORM public.invalidate_dating_for_user(NEW.user_id, -- Spec 2 W4a (§6.3): an underage_risk age_review closes every match as age_review
      CASE WHEN NEW.restriction_type = 'age_review' THEN 'age_review' ELSE 'account_restricted' END); -- Spec 2 W4a
   ELSIF NEW.restriction_type = 'moderation_hold' THEN -- Spec 2 W7a (§6.3): hidden from introductions, matches stay open
    PERFORM public.invalidate_dating_for_user(NEW.user_id, 'moderation_hold'); -- Spec 2 W7a: introductions only
   END IF; -- Spec 2 W7a: under_review shows nothing (generation leaves the person out)
  ELSIF TG_OP = 'UPDATE' AND NEW.lifted_at IS NOT NULL AND OLD.lifted_at IS NULL THEN -- Spec 2 W7a (R-53)
    PERFORM private.dating_release_suspension(NEW.user_id); -- Spec 2 W7a: an ended suspension becomes a pause
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dating_account_in_good_standing(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM auth.users au
    WHERE au.id = p_user_id
      AND au.deleted_at IS NULL
      AND (au.banned_until IS NULL OR au.banned_until <= now())
  ) AND NOT EXISTS (
    SELECT 1 FROM public.dating_account_restrictions dar
    WHERE dar.user_id = p_user_id
      AND dar.restriction_type <> 'under_review' -- Spec 2 W7a (§6.3): a closer look is never visible
      AND dar.lifted_at IS NULL
      AND dar.starts_at <= now()
      AND (dar.ends_at IS NULL OR dar.ends_at > now())
  ) AND NOT EXISTS ( -- Spec 2 W1a: a restriction carried past a deletion
    SELECT 1 FROM public.enforcement_records er
    WHERE er.scope = 'dating'
      AND er.restriction_type <> 'under_review' -- Spec 2 W7a
      AND er.phone_hmac = public.dating_phone_hmac_for_user(p_user_id)
      AND (er.effect_until IS NULL OR er.effect_until > now())
      AND er.purge_after > now()
  ) AND NOT EXISTS ( -- Spec 2 W1a: Spec 1's account holds (gate 3)
    SELECT 1 FROM public.account_holds h
    WHERE h.user_id = p_user_id
      AND h.kind IN ('age_review', 'safety_review')
      AND h.resolved_at IS NULL
  );
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
                   AND r.starts_at <= p_at AND (r.ends_at IS NULL OR r.ends_at > p_at)); -- Spec 2 W7a
$function$;

CREATE OR REPLACE FUNCTION private.dating_purge_steps()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT ARRAY['matches', 'introductions', 'pair_markers', -- Spec 2 W7a: and the report evidence and reports
               'report_evidence', 'reports', 'moderation_cases', 'opener_hashes', -- Spec 2 W7a
               'safety_events', 'safety_outbox', 'rate_limits', 'block_hmacs', 'enforcement_records',
               'session_context'];
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
         WHERE c.created_at < p_now - interval '2 years' AND c.state NOT IN ('open', 'in_review');
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

CREATE OR REPLACE FUNCTION private.dating_open_chat_case(p_sender uuid, p_match uuid, p_signal text, p_priority text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_opened boolean;
BEGIN
  v_opened := private.dating_open_signal_case(p_sender, p_signal, p_priority);
  IF v_opened THEN
    UPDATE public.dating_moderation_cases AS c SET match_id = p_match
     WHERE c.target_user_id = p_sender AND c.kind = 'signal' AND c.signal_kind = p_signal
       AND c.state IN ('open', 'in_review') AND c.match_id IS NULL;
  END IF;
  INSERT INTO public.dating_case_matches (case_id, match_id) -- Spec 2 W7a (W6 final M-16): a later hit's match too
  SELECT c.id, p_match FROM public.dating_moderation_cases AS c -- Spec 2 W7a
   WHERE p_match IS NOT NULL AND c.kind = 'signal' AND c.signal_kind = p_signal AND c.state IN ('open', 'in_review') -- Spec 2 W7a
     AND (c.target_user_id = p_sender OR c.target_phone_hmac = public.dating_phone_hmac_for_user(p_sender)) -- Spec 2 W7a
  ON CONFLICT DO NOTHING; -- Spec 2 W7a
  RETURN v_opened;
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_deletion_carry(p_user uuid, p_final boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_hmac constant text := public.dating_phone_hmac_for_user(p_user);
  v_n integer := 0;
  v_rows integer;
  v_live_fp text;
  v_stored_fp text;
BEGIN
  IF p_user IS NULL THEN
    RETURN 0;
  END IF;
  -- 1. Each live restriction becomes an enforcement record (once), under the
  --    HMAC stamped when it was placed (I-1).
  INSERT INTO public.enforcement_records (phone_hmac, scope, source_restriction_id, restriction_type,
                                          category, confirmed_report_count, effect_until, purge_after, case_id, -- Spec 2 W7a
                                          decided_by, appeal_submitted_at, appeal_decided_at, appeal_decided_by) -- Spec 2 W7a (Task 2 fix round 1, I-1, M-1)
  SELECT s.phone_hmac, 'dating', dar.id, dar.restriction_type, dar.category, -- Spec 2 W7a
         (SELECT count(*) FROM public.dating_reports AS r
           WHERE r.target_user_id = p_user AND to_jsonb(r) ->> 'state' = 'upheld')::int,
         dar.ends_at, now() + interval '2 years', dar.case_id, -- Spec 2 W7a
         dar.decided_by, ap.submitted_at, ap.decided_at, ap.decided_by -- Spec 2 W7a (Task 2 fix round 1): the decider, a rejected appeal
    FROM public.dating_account_restrictions AS dar
    JOIN private.dating_restriction_hmacs AS s ON s.restriction_id = dar.id
    LEFT JOIN public.dating_appeals AS ap ON ap.restriction_id = dar.id AND ap.state = 'rejected' -- Spec 2 W7a (Task 2 fix round 1, M-1)
   WHERE dar.user_id = p_user AND dar.lifted_at IS NULL
     AND (dar.ends_at IS NULL OR dar.ends_at > now())
  ON CONFLICT (source_restriction_id) DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  v_n := v_n + v_rows;
  IF v_hmac IS NOT NULL THEN
    -- 2. Block pairs by number, kept 2 years from now.
    INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
    SELECT h.blocker, h.blocked
      FROM (SELECT public.dating_phone_hmac_for_user(b.blocker_user_id) AS blocker,
                   public.dating_phone_hmac_for_user(b.blocked_user_id) AS blocked
              FROM public.dating_blocks AS b
             WHERE p_user IN (b.blocker_user_id, b.blocked_user_id)) AS h
     WHERE h.blocker IS NOT NULL AND h.blocked IS NOT NULL
    ON CONFLICT (blocker_hmac, blocked_hmac) DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_n := v_n + v_rows;
    v_n := v_n + (SELECT count(*)::int FROM public.dating_block_hmacs AS p
                   WHERE v_hmac IN (p.blocker_hmac, p.blocked_hmac) AND p.purge_after IS NULL);
    UPDATE public.dating_block_hmacs
       SET purge_after = now() + interval '2 years'
     WHERE v_hmac IN (blocker_hmac, blocked_hmac);
    -- Spec 2 W7a (R-52): the person's matches keep the number's code, so the other
    -- Spec 2 W7a can still report them for 30 days. (Task 2, O-1) In a block of its
    -- Spec 2 W7a own: a lock conflict on a match row loses only the stamp (counted;
    -- Spec 2 W7a the delete's own carry stamps again), never the records above.
    BEGIN -- Spec 2 W7a (Task 2, O-1)
    UPDATE public.dating_matches AS m SET low_phone_hmac = v_hmac -- Spec 2 W7a
     WHERE m.user_low_id = p_user AND m.low_phone_hmac IS NULL; -- Spec 2 W7a
    UPDATE public.dating_matches AS m SET high_phone_hmac = v_hmac -- Spec 2 W7a
     WHERE m.user_high_id = p_user AND m.high_phone_hmac IS NULL; -- Spec 2 W7a
    EXCEPTION WHEN OTHERS THEN -- Spec 2 W7a (Task 2, O-1)
      PERFORM private.bump_metric_internal('dating.deletion.stamp_failed'); -- Spec 2 W7a (Task 2, O-1)
    END; -- Spec 2 W7a (Task 2, O-1)
    -- 4. Reports about the person keep the number's HMAC (the cascade sets
    --    reporter and target ids to NULL); an HMAC already there is kept.
    BEGIN -- Spec 2 W7a (Task 2 fix round 1, M-10): in a block of its own, as the match stamp
    UPDATE public.dating_reports AS r
       SET target_phone_hmac = v_hmac
     WHERE r.target_user_id = p_user AND r.target_phone_hmac IS NULL;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_n := v_n + v_rows;
    EXCEPTION WHEN OTHERS THEN -- Spec 2 W7a (Task 2 fix round 1, M-10)
      PERFORM private.bump_metric_internal('dating.deletion.stamp_failed'); -- Spec 2 W7a (Task 2 fix round 1, M-10)
    END; -- Spec 2 W7a (Task 2 fix round 1, M-10)
  END IF;

  IF p_final THEN
    -- A live restriction with no stamp could not carry (PF-F6): counted
    -- once, at the deletion itself.
    IF EXISTS (SELECT 1 FROM public.dating_account_restrictions AS dar
                WHERE dar.user_id = p_user AND dar.lifted_at IS NULL
                  AND (dar.ends_at IS NULL OR dar.ends_at > now())
                  AND NOT EXISTS (SELECT 1 FROM private.dating_restriction_hmacs AS s
                                   WHERE s.restriction_id = dar.id)) THEN
      PERFORM private.bump_metric_internal('dating.deletion.uncarried');
    END IF;
    -- The key the survivors were written under, for an account with a
    -- Dating footprint: read, never stored (M-7).
    v_live_fp := public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1');
    IF v_live_fp IS NOT NULL AND (
         EXISTS (SELECT 1 FROM public.dating_account_restrictions AS dar WHERE dar.user_id = p_user)
         OR EXISTS (SELECT 1 FROM public.dating_blocks AS b WHERE p_user IN (b.blocker_user_id, b.blocked_user_id))
         OR EXISTS (SELECT 1 FROM public.dating_reports AS r WHERE r.target_user_id = p_user)) THEN
      SELECT k.fingerprint INTO v_stored_fp
        FROM private.dating_key_fingerprints AS k WHERE k.name = 'dating_exclusion_key';
      IF v_stored_fp IS NULL THEN
        PERFORM private.bump_metric_internal('dating.exclusion_key.unseeded');
      ELSIF v_stored_fp IS DISTINCT FROM v_live_fp THEN
        PERFORM private.bump_metric_internal('dating.exclusion_key.mismatch');
      END IF;
    END IF;
  END IF;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_dating_matches(p_include_ended boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_rows jsonb;
  v_ended jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT coalesce(pg_catalog.jsonb_agg(c.row ORDER BY c.at DESC, c.id), '[]'::jsonb) INTO v_rows
    FROM (SELECT m.id, coalesce(l.created_at, m.matched_at) AS at,
                 pg_catalog.jsonb_build_object(
                   'match_id', m.id,
                   'display_name', (SELECT p.display_name FROM public.dating_profiles AS p WHERE p.user_id = s.other),
                   'age', public.account_age(s.other),
                   'last', CASE WHEN l.id IS NULL THEN NULL ELSE
                             private.dating_message_json(l, s.side, m.low_swap_at IS NOT NULL AND m.high_swap_at IS NOT NULL) END,
                   'new', EXISTS (SELECT 1 FROM public.dating_messages AS d
                                   WHERE d.match_id = m.id AND d.sender_side <> s.side
                                     AND private.dating_message_visible(d, s.side) -- Spec 2 W6c
                                     AND d.created_at > coalesce(s.seen, '-infinity'))) AS row
            FROM public.dating_matches AS m
           CROSS JOIN LATERAL (SELECT CASE WHEN m.user_low_id = v_user THEN 'low' ELSE 'high' END AS side,
                                      CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END AS other,
                                      CASE WHEN m.user_low_id = v_user THEN m.low_seen_at ELSE m.high_seen_at END AS seen) AS s
            LEFT JOIN LATERAL (SELECT d.* FROM public.dating_messages AS d WHERE d.match_id = m.id
                                  AND private.dating_message_visible(d, s.side) -- Spec 2 W6c
                                ORDER BY d.created_at DESC, d.id DESC LIMIT 1) AS l ON true
           WHERE v_user IN (m.user_low_id, m.user_high_id) AND m.state = 'active' AND s.other IS NOT NULL
             AND NOT private.dating_pair_blocked(m.user_low_id, m.user_high_id)) AS c; -- fix round 1 (M-5)
  IF coalesce(p_include_ended, false) THEN
    SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'match_id', m.id,
             'display_name', (SELECT p.display_name FROM public.dating_profiles AS p
                               WHERE p.user_id = CASE WHEN m.user_low_id = v_user THEN m.user_high_id ELSE m.user_low_id END),
             'ended_at', e.at) ORDER BY e.at DESC, m.id), '[]'::jsonb) -- Spec 2 W7a (W7b Task 5 fix round 1, R-T3-3): the end
      INTO v_ended
      FROM public.dating_matches AS m
     CROSS JOIN LATERAL (SELECT coalesce(CASE WHEN m.state = 'active' -- Spec 2 W7a (R-T3-3): a chat only a block ended, from the block
                                              THEN private.dating_pair_blocked_since(m.user_low_id, m.user_high_id) END, -- Spec 2 W7a
                                         m.closed_at, m.matched_at) AS at) AS e -- Spec 2 W7a
     WHERE v_user IN (m.user_low_id, m.user_high_id)
       AND (((m.state <> 'active' OR m.user_low_id IS NULL OR m.user_high_id IS NULL) AND m.evidence_until > now()) -- Spec 2 W7a
            OR (m.state = 'active' -- Spec 2 W7a (W6 T2 N-4; fix round 1, M-8): a chat only a block ended, for 30 days from it
                AND private.dating_pair_blocked_since(m.user_low_id, m.user_high_id) > now() - interval '30 days')); -- Spec 2 W7a
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'conversations', v_rows)
      || CASE WHEN coalesce(p_include_ended, false) THEN pg_catalog.jsonb_build_object('ended', v_ended) ELSE '{}'::jsonb END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_dating_safety_job(p_message_id uuid, p_version text, p_hits jsonb, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_d public.dating_messages;
  v_m public.dating_matches;
  v_to uuid;
  v_from uuid;
  v_attempts smallint;
  h jsonb;
  v_family text;
  v_tier integer;
  v_events integer := 0;
  v_hash text;
  v_cfg jsonb;
  v_fin boolean := false;
  v_sex boolean := false;
BEGIN
  IF p_message_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT o.attempts INTO v_attempts FROM public.dating_message_safety_outbox AS o
   WHERE o.message_id = p_message_id AND o.state = 'processing' FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_claimed');
  END IF;
  IF p_error IS NOT NULL THEN
    UPDATE public.dating_message_safety_outbox AS o
       SET state = CASE WHEN v_attempts >= 5 THEN 'dead_letter' ELSE 'pending' END,
           last_error_code = CASE WHEN p_error ~ '^[a-z0-9_]{1,40}$' THEN p_error ELSE 'worker_error' END,
           processing_started_at = NULL
     WHERE o.message_id = p_message_id;
    IF v_attempts >= 5 THEN
      PERFORM private.bump_metric_internal('dating.safety.dead_letter');
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', true, 'state', CASE WHEN v_attempts >= 5 THEN 'dead_letter' ELSE 'pending' END);
  END IF;
  -- Its own IF first: an OR has no order, and the elements of a non-array raise.
  IF jsonb_typeof(coalesce(p_hits, '[]'::jsonb)) <> 'array' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  -- A version names a stored config, and each hit's tier is its family's
  -- tier there (a hit can't skip its case); a hit with no family is invalid
  -- (NULL NOT IN is NULL: coalesced), never a raise that holds the message.
  IF p_version IS NOT NULL THEN
    SELECT c.config INTO v_cfg FROM public.dating_safety_configs AS c WHERE c.version = p_version;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
    END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(p_hits, '[]'::jsonb)) AS x
              WHERE jsonb_typeof(x) <> 'object' OR coalesce(x ->> 'family', '') NOT IN ('sexual_pressure', 'harassment_abuse',
                      'contact_migration_pressure', 'meet_private_pressure', 'threat_intimidation', 'financial_request',
                      'sextortion', 'child_access', 'age_signal', 'identity_inconsistency')
                 OR coalesce(x ->> 'tier', '') NOT IN ('1', '2', '3')
                 OR (x ->> 'tier') IS DISTINCT FROM (v_cfg #>> ARRAY['families', x ->> 'family', 'tier'])
                 -- Fix round 1 (M-5): the rule is its family and one of that
                 -- version's terms, never free text (no message words).
                 OR NOT EXISTS (
                      SELECT 1 FROM jsonb_array_elements_text(
                               CASE WHEN jsonb_typeof(v_cfg #> ARRAY['families', x ->> 'family', 'terms']) = 'array'
                                    THEN v_cfg #> ARRAY['families', x ->> 'family', 'terms'] ELSE '[]'::jsonb END
                               || CASE WHEN jsonb_typeof(v_cfg #> ARRAY['families', x ->> 'family', 'new_match_terms']) = 'array'
                                       THEN v_cfg #> ARRAY['families', x ->> 'family', 'new_match_terms'] ELSE '[]'::jsonb END) AS t(term)
                       WHERE (x ->> 'family') || ':' || t.term = x ->> 'rule_id')
                 OR coalesce(pg_catalog.char_length(x ->> 'rule_id'), 0) NOT BETWEEN 1 AND 120)
     OR (p_version IS NULL AND jsonb_array_length(coalesce(p_hits, '[]'::jsonb)) > 0) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT * INTO v_d FROM public.dating_messages AS d WHERE d.id = p_message_id;
  SELECT * INTO v_m FROM public.dating_matches AS m WHERE m.id = v_d.match_id;
  v_from := v_d.sender_user_id;
  v_to := CASE WHEN v_d.sender_side = 'low' THEN v_m.user_high_id ELSE v_m.user_low_id END;
  IF p_version IS NULL THEN
    PERFORM private.bump_metric_internal('dating.safety.no_config');
  END IF;
  FOR h IN SELECT x FROM jsonb_array_elements(coalesce(p_hits, '[]'::jsonb)) AS x LOOP
    v_family := h ->> 'family';
    v_tier := (h ->> 'tier')::integer;
    -- Fix round 1 (M-7): a recipient deleted meanwhile (v_to NULL) still
    -- leaves the evidence and the case about the sender; no card.
    INSERT INTO public.dating_safety_events (match_id, message_id, at_risk_user_id, sender_user_id, rule_id, family, tier,
                                             config_version, source_event_key)
    VALUES (v_d.match_id, p_message_id, v_to, v_from, h ->> 'rule_id', v_family, v_tier, p_version,
            p_message_id::text || ':' || (h ->> 'rule_id'))
    ON CONFLICT (source_event_key) DO NOTHING;
    IF FOUND THEN
      v_events := v_events + 1;
      v_fin := v_fin OR v_family = 'financial_request';
      v_sex := v_sex OR v_family = 'sexual_pressure';
      IF v_from IS NOT NULL AND v_family IN ('sexual_pressure', 'financial_request') THEN -- Spec 2 W7a (fix round 1, I-1, §6.2): the
        PERFORM private.dating_report_retrip(v_from, v_d.match_id, v_family); -- Spec 2 W7a sender's reports from this match stop counting
      END IF; -- Spec 2 W7a
      IF v_tier <= 2 AND v_to IS NOT NULL THEN
        PERFORM private.bump_metric_internal('dating.card.' || v_family);
        -- Task 7 fix round 1: the recipient's open chat reads again and
        -- shows the card (the sender's chat learns nothing).
        -- Spec 2 W6c (final server fix, I-7): only once the recipient can see the message: a guided
        -- Spec 2 W6c answer not shown yet has no card to show (the reveal tells both chats).
        IF private.dating_message_visible(v_d, CASE WHEN v_d.sender_side = 'low' THEN 'high' ELSE 'low' END) THEN -- Spec 2 W6c
          PERFORM private.dating_bump_chat(v_to, v_d.match_id); -- Spec 2 W6c
        END IF; -- Spec 2 W6c
      END IF;
      IF v_tier >= 2 AND v_from IS NOT NULL THEN
        PERFORM private.dating_open_chat_case(v_from, v_d.match_id, 'chat_' || v_family,
          CASE WHEN v_family = 'identity_inconsistency' THEN 'P2' ELSE 'P1' END);
      END IF;
    END IF;
  END LOOP;
  -- §5.10 (carry 8): the sender's repeated patterns, each a signal case.
  -- Fix round 1 (I-1): each pattern is checked only when this completion
  -- added its evidence (the opener: the side's first message), so the case
  -- names the match that holds it; evidence a moderator's decision
  -- postdates never counts again (W5c's dating_signal_cleared, per item):
  -- a decision sticks, and only fresh evidence opens a new case. A deleted
  -- recipient still counts once (by match, else by event; M-7).
  IF v_from IS NOT NULL THEN
    IF v_fin AND (SELECT count(DISTINCT coalesce(e.at_risk_user_id::text, 'm:' || e.match_id::text, 'e:' || e.id::text))
                    FROM public.dating_safety_events AS e
                   WHERE e.sender_user_id = v_from AND e.family = 'financial_request' AND e.created_at > now() - interval '7 days'
                     AND NOT private.dating_signal_cleared(v_from, 'money_asks', e.created_at)) >= 2 THEN
      PERFORM private.dating_open_chat_case(v_from, v_d.match_id, 'money_asks', 'P1');
    END IF;
    IF v_sex AND (SELECT count(DISTINCT coalesce(e.at_risk_user_id::text, 'm:' || e.match_id::text, 'e:' || e.id::text))
                    FROM public.dating_safety_events AS e
                   WHERE e.sender_user_id = v_from AND e.family = 'sexual_pressure' AND e.created_at > now() - interval '7 days'
                     AND NOT private.dating_signal_cleared(v_from, 'sexual_pressure', e.created_at)) >= 2 THEN
      PERFORM private.dating_open_chat_case(v_from, v_d.match_id, 'sexual_pressure', 'P2');
    END IF;
    -- Fix round 2 (N-1): the side's first text message (send keeps that
    -- one's opener), whatever guided answers came before it.
    IF v_d.kind = 'text' AND NOT EXISTS (SELECT 1 FROM public.dating_messages AS d2
                    WHERE d2.match_id = v_d.match_id AND d2.sender_side = v_d.sender_side AND d2.kind = 'text'
                      AND (d2.created_at, d2.id) < (v_d.created_at, v_d.id)) THEN
      SELECT k.hash INTO v_hash FROM public.dating_opener_hashes AS k WHERE k.sender_user_id = v_from AND k.match_id = v_d.match_id;
      IF v_hash IS NOT NULL
         AND (SELECT count(DISTINCT k.match_id) FROM public.dating_opener_hashes AS k
               WHERE k.sender_user_id = v_from AND k.hash = v_hash AND k.created_at > now() - interval '7 days'
                 AND NOT private.dating_signal_cleared(v_from, 'duplicate_opener', k.created_at)) >= 3 THEN
        PERFORM private.dating_open_chat_case(v_from, v_d.match_id, 'duplicate_opener', 'P2');
      END IF;
    END IF;
  END IF;
  UPDATE public.dating_message_safety_outbox AS o
     SET state = 'done', completed_at = clock_timestamp(), processing_started_at = NULL, last_error_code = NULL
   WHERE o.message_id = p_message_id;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'state', 'done', 'events', v_events);
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
                        'dating.moderation.csam_lift']) AS k(key)), -- Spec 2 W7a (W7c Task 8: the CSAM hold lift, R-57)
    -- Spec 2 W7a (§6.2): open report and appeal cases by priority, past their clock,
    -- Spec 2 W7a and reports about a number with no code (the key was missing).
    'reports_open',(SELECT jsonb_build_object( -- Spec 2 W7a
                      'P0', count(*) FILTER (WHERE c.priority = 'P0'), 'P1', count(*) FILTER (WHERE c.priority = 'P1'), -- Spec 2 W7a
                      'P2', count(*) FILTER (WHERE c.priority = 'P2'), 'P3', count(*) FILTER (WHERE c.priority = 'P3'), -- Spec 2 W7a
                      'past_due', count(*) FILTER (WHERE c.sla_due_at < now())) -- Spec 2 W7a
                    FROM public.dating_moderation_cases AS c -- Spec 2 W7a
                   WHERE c.kind IN ('report', 'appeal') AND c.state IN ('open', 'in_review')), -- Spec 2 W7a
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

CREATE OR REPLACE FUNCTION public.get_dating_home()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country text;
  v_region text;
  v_config public.country_safety_config;
  v_enrol public.dating_enrollments;
  v_opens timestamptz;
  v_after timestamptz;
  v_err text;
  v_undated boolean; -- Spec 2 W3a (fix round 1, M-2, M-4)
  v_cand text; -- Spec 2 W3a
  v_has jsonb; -- Spec 2 W3a (C-2)
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_has := jsonb_build_object('has_data', private.dating_has_data(v_user)) -- Spec 2 W7a: and an accepted appeal (§3.7), only when there is one
           || CASE WHEN private.dating_appeal_accepted(v_user) THEN jsonb_build_object('appeal_accepted', true) ELSE '{}'::jsonb END; -- Spec 2 W7a
  v_reason := public.dating_eligibility(v_user, 'setup');
  SELECT p.country_code::text, p.region_code INTO v_country, v_region
    FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'feature_unavailable' THEN
    IF public.dating_require_trusted_device() IS NOT TRUE THEN -- Spec 2 W4b (fix round 1, M-4): nothing about the person to another phone
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'feature_unavailable'); -- Spec 2 W4b
    END IF; -- Spec 2 W4b
    v_country := coalesce(v_country, private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = v_user))); -- Spec 2 W3a
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'feature_unavailable', 'country', v_country, -- Spec 2 W3a (C-2)
      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a (R-4, R-5)
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'reverify_device', -- Spec 2 W3a (C-2); Spec 2 W4b
      'variant', private.dating_reverify_variant(v_user)); -- Spec 2 W4b (§3.3.4): setup_restart or verified
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'account_unavailable' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', private.dating_unavailable_state(v_user)); -- Spec 2 W3a (C-2)
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'country_closed' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'country_closed', 'country', v_country, -- Spec 2 W3a (C-2)
      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'region_closed' THEN
    v_config := public.dating_country_config(v_country);
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'region_closed', 'country', v_country, 'region', v_region, -- Spec 2 W3a (C-2)
      'open_regions', to_jsonb(coalesce(v_config.open_regions, ARRAY[]::text[])), -- Spec 2 W3a
      'notify', private.dating_notice_state(v_user, v_country, v_region)); -- Spec 2 W3a
  END IF;
  SELECT * INTO v_enrol FROM public.dating_enrollments AS e WHERE e.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'relationship_active' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || CASE WHEN v_enrol.state = 'paused' -- Spec 2 W3a (C-2)
                THEN jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason, -- Spec 2 W3a (fix round 1, M-3)
                                        'can_resume', false) -- Spec 2 W3a (T4 fix round 1, I-2): a shared space is open now
                     || private.dating_check_standing(v_user, v_enrol.pause_reason) -- Spec 2 W4b (T3 M-4): where the check stands
                     || CASE WHEN v_enrol.pause_reason = 'same_gender_switch' THEN jsonb_build_object('country', v_country) -- Spec 2 W3a
                             ELSE '{}'::jsonb END -- Spec 2 W3a
                ELSE jsonb_build_object('state', 'unavailable') END;
  END IF;
  IF v_reason IS DISTINCT FROM 'eligible' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- an unknown or NULL reason fails closed -- Spec 2 W3a (C-2)
  END IF;
  IF v_enrol.state = 'suspended' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- suspended without a live restriction (W7a routes it) -- Spec 2 W3a (C-2)
  END IF;
  IF v_enrol.state = 'paused' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason, -- Spec 2 W3a (C-2)
      'can_resume', coalesce(v_enrol.pause_reason IS DISTINCT FROM 'verification' OR public.dating_age_gate_holds(v_user), false)) -- Spec 2 W4a (fix round 1, M-2): a verification pause resumes once the check holds; W3a (T4 fix round 1, I-2): no shared space holds it
      || private.dating_check_standing(v_user, v_enrol.pause_reason) -- Spec 2 W4b (T3 M-4): where the check stands
      || CASE WHEN v_enrol.pause_reason = 'same_gender_switch' THEN jsonb_build_object('country', v_country) -- Spec 2 W3a (the §2.4 note)
              ELSE '{}'::jsonb END; -- Spec 2 W3a
  END IF;
  v_opens := private.dating_gentle_wait_opens_at(v_user);
  v_undated := EXISTS (SELECT 1 FROM public.relationships AS r -- Spec 2 W3a (fix round 1, M-2, M-4): an ending with no date
                       WHERE v_user IN (r.user_a, r.user_b) AND r.status = 'ended' AND r.ended_at IS NULL); -- Spec 2 W3a
  IF v_enrol.state = 'active' THEN
    -- Spec 2 W3a (fix round 1, M-2): read here, so a home read never
    -- Spec 2 W3a reaches the candidate check's undated-ending counter.
    IF v_undated THEN -- Spec 2 W3a
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a (M-2)
    END IF; -- Spec 2 W3a (M-2)
    -- Spec 2 W3a (W2 carry): never "you're live" while the candidate check
    -- Spec 2 W3a refuses for anything but the wait (an undated ending, a
    -- Spec 2 W3a path off Dating); the wait itself is the cool-off below.
    v_cand := public.dating_eligibility(v_user, 'candidate'); -- Spec 2 W3a
    IF v_cand IS DISTINCT FROM 'eligible' AND v_cand IS DISTINCT FROM 'gentle_wait' THEN -- Spec 2 W3a
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a
    END IF; -- Spec 2 W3a
    -- The first drop is the later of the open date and the 72 h cool-off
    -- from account creation (§2.1, §2.8).
    v_after := greatest(coalesce(v_opens, '-infinity'::timestamptz),
                        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours');
    IF v_after > now() THEN
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'cool_off', 'first_drop_at', private.dating_first_drop_at(v_user, v_after)); -- Spec 2 W3a (C-2)
    END IF;
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'active'); -- Spec 2 W3a (C-2)
  END IF;
  IF v_opens IS NOT NULL THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'gentle_wait', 'ended_at', (v_opens AT TIME ZONE 'UTC' - interval '30 days') AT TIME ZONE 'UTC', 'opens_at', v_opens, -- in UTC (a DST change moves nothing) -- Spec 2 W3a (C-2)
                              'next_step', private.dating_next_step(v_user), -- Spec 2 W3a
                              'can_shorten', coalesce(private.dating_gentle_wait_can_shorten(v_user), false), -- Spec 2 W3a (carry 8)
                              'first_drop_at', private.dating_first_drop_at(v_user, greatest(v_opens, now(), -- Spec 2 W3a
                                (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours'))); -- Spec 2 W3a
  END IF;
  IF private.dating_next_step(v_user) IS NOT DISTINCT FROM 'how' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'not_started', -- Spec 2 W3a (D1 line 6)
      'first_drop_at', CASE WHEN v_undated THEN NULL -- Spec 2 W3a (fix round 1, M-4): no date to promise
        ELSE private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a
        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours')) END); -- Spec 2 W3a
  END IF;
  IF private.dating_next_step(v_user) IS NOT DISTINCT FROM 'verify' -- Spec 2 W4a (§3.1): a person or the ID vendor is checking
     AND EXISTS (SELECT 1 FROM public.dating_verification_sessions AS vs -- Spec 2 W4a
                  WHERE vs.user_id = v_user AND vs.kind = 'activation' AND vs.state = 'awaiting_review') THEN -- Spec 2 W4a
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'verifying', 'next_step', 'verify'); -- Spec 2 W4a
  END IF; -- Spec 2 W4a
  RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'setup_in_progress', 'next_step', private.dating_next_step(v_user), -- Spec 2 W3a (C-2)
    'first_drop_at', CASE WHEN v_undated THEN NULL -- Spec 2 W3a (D13; fix round 1, M-4)
      ELSE private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a
      (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours')) END); -- Spec 2 W3a
EXCEPTION WHEN raise_exception THEN
  -- An unreadable field or a missing field key is no state the person can
  -- act on: the neutral 'unavailable', never a raw error. Anything else raises.
  -- Every re-creation keeps this handler (W4, W5, W7, W8 add decrypting
  -- readers; nothing in v1's call graph decrypts yet). Counted best-effort.
  v_err := SQLERRM;
  IF v_err IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
    BEGIN
      PERFORM private.bump_metric_internal(CASE WHEN v_err = 'dating:field_key_missing'
                                                THEN 'dating.field_key.missing' ELSE 'dating.home.unreadable_field' END);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a (C-2)
  END IF;
  RAISE;
END;
$function$;

-- ---------------------------------------------------------------------
-- 14. Self-revoke (the W6 final pattern): nothing this migration creates
--     is any API role's until the twin grants it.
-- ---------------------------------------------------------------------
REVOKE ALL ON TABLE public.dating_report_evidence, public.dating_case_matches, public.dating_appeals
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  private.dating_report_priority(text), private.dating_report_sla_due(text, timestamptz),
  private.dating_report_defaults(), private.dating_restriction_defaults(),
  private.dating_reporter_tripped(uuid, uuid), private.dating_report_excluded(uuid),
  private.dating_snapshot_evidence(uuid, uuid, text), private.dating_report_case(uuid),
  private.dating_report_corroborated(uuid),
  private.dating_place_restriction(uuid, text, text, text, uuid, uuid, timestamptz, boolean),
  private.dating_file_report(uuid, uuid, text, uuid, uuid, text, text, text, text), private.dating_report_answer(uuid),
  private.dating_release_suspension(uuid), private.dating_close_case(uuid, uuid, text),
  private.dating_report_retrip(uuid, uuid, text), private.dating_report_reply(uuid, boolean),
  private.dating_pair_blocked_since(uuid, uuid), private.dating_lock_setup_pair(uuid, uuid),
  private.dating_report_limited(uuid),
  public.report_dating_match(text, uuid, text, text, boolean),
  public.report_dating_introduction(text, uuid, text, text, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  private.dating_carry_over(uuid), private.dating_release_expired_suspensions(),
  public.get_my_dating_restriction(), private.dating_appeal_accepted(uuid),
  public.submit_dating_appeal(text, uuid, text),
  private.dating_decide_appeal(uuid, uuid, boolean, boolean)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
