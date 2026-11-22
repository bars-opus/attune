-- Spec 2 W7b (§4.3, §4.4 moderation_*, §4.6 dating-moderation-sla, §4.9
-- W7b, §6.4, §6.5, §7.1 routing rows, §7.5 mutant 26; S-5): the console's
-- server side.
--   * dating_moderators (role, sensitive_routing_allowed, languages,
--     active) and dating_moderation_actions, append-only (a trigger
--     refuses every UPDATE, and every DELETE but the purge's, at 2 years).
--   * Read-time sensitive routing (S-5): dating_case_needs_sensitive_routing
--     decrypts the identities of the people a case puts side by side (the
--     members of its matches, its reporters; an appeal: its restriction's
--     case too) inside the transaction and answers only true or false; a
--     case it answers true for is left out of the queue, and refused on open
--     with the ordinary case_unavailable, for anyone without
--     sensitive_routing_allowed. Nothing about routing is stored, logged or
--     written to the audit. An unknown identity routes (fails closed).
--   * moderation_* functions, the service role's alone, called only by the
--     dating-moderation edge function with the moderator's id: whoami, the
--     queue, claim, the case, dismiss, hold, lift a hold, restrict, ask for
--     ID, confirm a minor (Spec 1's age_review account hold, §6.3), a note,
--     decide an appeal, photos, verifications, countries (publish: the
--     safety owner only), S1 W9b's Opinions review queue v0 through its own
--     two RPCs, the audit log. Every action writes one audit row.
--   * Task 5 (W7a carries): every console write takes the person's setup
--     lock before any row (the order every Dating writer keeps, W7a M-11,
--     N-1), then the case row; a replayed action (the edge function's
--     retry after a lost answer) answers as the first did and writes no
--     second audit row (Task 2 M-11); an appeal of a restriction nobody is
--     recorded as deciding reads decider_unknown until the safety owner may
--     decide it, 24 hours on (R1-3); the audit log and a case's prior cases
--     leave out a routed case for anyone without routing (S-5: a case's
--     existence is not inferred); not_moderator is counted on every
--     function.
--   * Task 5 fix round 1: a decision lifts every hold its case placed
--     (a CSAM hold excepted), an accepted appeal its case's; Lift hold
--     acts on its own case only, never a closed one; a moderator who is a
--     party to a case (its person, a reporter, anyone in its chats, by
--     account or number) never sees or acts on it, nor on their own photo
--     or check (counted); a routed open earlier case is left out without
--     routing; every write waits at most 2 s, then answers busy (counted);
--     a claim takes over another's live claim only for the safety owner or
--     after an hour, and says so; a replayed publish publishes once.
--   * dating_moderation_sla_check() and its cron (every 15 minutes): a
--     content-free alert per priority past its clock ("P0 case waiting 3 h
--     40 m") to app_setting('moderation_alert_webhook'), counted when unset.
-- Nothing here turns a flag on or names a moderator (the owner adds rows).
-- Grants in 20261121110010_dating_v2_moderation_console_grants.sql; this
-- file revokes what it creates from every API role first.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------------
-- 1. Moderators and the audit log.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dating_moderators (
  user_id uuid PRIMARY KEY REFERENCES public.users (id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('moderator', 'safety_owner')),
  sensitive_routing_allowed boolean NOT NULL DEFAULT false,
  languages text[] NOT NULL DEFAULT '{}',
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.dating_moderators ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.dating_moderation_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid REFERENCES public.dating_moderation_cases (id) ON DELETE SET NULL,
  actor_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN (
    'open_case', 'claim', 'dismiss', 'hold', 'lift_hold', 'restrict', 'ask_for_id', 'confirm_minor', 'note',
    'decide_appeal', 'photo_decide', 'verification_decide', 'publish_country', 'opinions_view', 'opinions_remove',
    'escalation', 'law_enforcement_request')),
  target_user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(detail) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS dating_moderation_actions_case_idx ON public.dating_moderation_actions (case_id);
CREATE INDEX IF NOT EXISTS dating_moderation_actions_created_idx ON public.dating_moderation_actions (created_at DESC);
-- Task 5 (M-11): a replay is found by the moderator's own rows.
CREATE INDEX IF NOT EXISTS dating_moderation_actions_actor_idx
  ON public.dating_moderation_actions (actor_id, action, created_at DESC);
ALTER TABLE public.dating_moderation_actions ENABLE ROW LEVEL SECURITY;

-- Append-only: no UPDATE but a foreign key's own SET NULL (the case
-- purged, the person's account deleted), nothing else changed; a DELETE
-- only from the purge (it sets attune.dating_audit_purge for its own
-- transaction) and only at 2 years.
CREATE OR REPLACE FUNCTION private.dating_moderation_actions_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.id = OLD.id AND NEW.actor_id = OLD.actor_id AND NEW.action = OLD.action
     AND NEW.detail = OLD.detail AND NEW.created_at = OLD.created_at
     AND (NEW.case_id IS NULL OR NEW.case_id = OLD.case_id)
     AND (NEW.target_user_id IS NULL OR NEW.target_user_id = OLD.target_user_id)
     AND (NEW.case_id IS DISTINCT FROM OLD.case_id OR NEW.target_user_id IS DISTINCT FROM OLD.target_user_id) THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' AND current_setting('attune.dating_audit_purge', true) = 'on'
     AND OLD.created_at < now() - interval '2 years' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'audit:append_only' USING ERRCODE = '42501';
END;
$$;
DROP TRIGGER IF EXISTS dating_moderation_actions_append_only ON public.dating_moderation_actions;
CREATE TRIGGER dating_moderation_actions_append_only
  BEFORE UPDATE OR DELETE ON public.dating_moderation_actions
  FOR EACH ROW EXECUTE FUNCTION private.dating_moderation_actions_guard();

CREATE OR REPLACE FUNCTION private.dating_audit(p_actor uuid, p_case uuid, p_action text, p_target uuid,
                                                p_detail jsonb DEFAULT '{}'::jsonb)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO public.dating_moderation_actions (case_id, actor_id, action, target_user_id, detail)
  VALUES (p_case, p_actor, p_action, (SELECT u.id FROM public.users AS u WHERE u.id = p_target),
          coalesce(p_detail, '{}'::jsonb));
$$;

CREATE OR REPLACE FUNCTION private.dating_moderator(p_actor uuid)
RETURNS public.dating_moderators
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT m.* FROM public.dating_moderators AS m WHERE m.user_id = p_actor AND m.active;
$$;

-- Task 5 (Task 2 M-11): [p_actor] already took [p_action] on [p_case]
-- (NULL: an action on no case) with at least this detail. A replayed call
-- (the edge function retrying after a lost answer) answers as the first
-- did and writes no second row.
CREATE OR REPLACE FUNCTION private.dating_moderation_replayed(p_actor uuid, p_case uuid, p_action text,
                                                              p_detail jsonb DEFAULT '{}'::jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_moderation_actions AS a
                  WHERE a.actor_id = p_actor AND a.action = p_action AND a.case_id IS NOT DISTINCT FROM p_case
                    AND a.detail @> coalesce(p_detail, '{}'::jsonb));
$$;

-- Task 5 fix round 1 (I-2, §6.2): [p_mod] is a party to [p_case]: its
-- person, a reporter on it, or one of the people in its chats (its match
-- and every linked one), by account or by number; for an appeal, a party
-- to its restriction's case too. A party never sees the case (the reporter
-- is never shown to the person they reported, nor a person their own
-- case).
CREATE OR REPLACE FUNCTION private.dating_case_party(p_mod uuid, p_case uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
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
  RETURN false;
END;
$$;

-- ---------------------------------------------------------------------
-- 2. Read-time sensitive routing (S-5).
-- ---------------------------------------------------------------------
-- A person's own identity answer ('woman', 'man', ...), or the one held
-- through a move; NULL when there is none or it can't be read.
CREATE OR REPLACE FUNCTION private.dating_identity_of(p_user uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN (SELECT private.dating_field_decrypt(coalesce(s.identity_enc, s.held_identity_enc)) ->> 'identity'
            FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user);
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

-- True when the case puts side by side two people who are not a woman and
-- a man, or when anyone it concerns can't be read: only this boolean ever
-- leaves the function.
CREATE OR REPLACE FUNCTION private.dating_case_needs_sensitive_routing(p_case uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
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
$$;

-- The case as [p_mod] may see it: NULL when it doesn't exist, needs the
-- routing they lack, or they are a party to it (one answer for all).
CREATE OR REPLACE FUNCTION private.dating_case_for(p_mod public.dating_moderators, p_case uuid)
RETURNS public.dating_moderation_cases
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT c.* FROM public.dating_moderation_cases AS c
   WHERE p_mod.user_id IS NOT NULL AND c.id = p_case
     AND NOT private.dating_case_party(p_mod.user_id, c.id) -- Task 5 fix round 1 (I-2)
     AND (p_mod.sensitive_routing_allowed OR NOT private.dating_case_needs_sensitive_routing(c.id));
$$;

-- Task 5 (W7a M-11, N-1): the case [p_mod] may act on, for a write: the
-- person's setup lock first (the lock every Dating writer of their rows
-- takes before any row: their own Block, Leave, deletion and Close kindly,
-- a report, a CSAM path), then the case row, read again under it (a
-- concurrent decision or a replay is seen). NULL as dating_case_for.
CREATE OR REPLACE FUNCTION private.dating_case_lock(p_mod public.dating_moderators, p_case uuid)
RETURNS public.dating_moderation_cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c public.dating_moderation_cases := private.dating_case_for(p_mod, p_case);
BEGIN
  IF c.id IS NOT NULL THEN
    IF c.target_user_id IS NOT NULL THEN
      PERFORM private.dating_lock_setup(c.target_user_id);
    END IF;
    SELECT x.* INTO c FROM public.dating_moderation_cases AS x WHERE x.id = c.id FOR UPDATE;
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
$$;

-- A report's evidence, decrypted (the messages only; NULL when unreadable).
CREATE OR REPLACE FUNCTION private.dating_evidence_messages(p_report uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN (SELECT private.dating_field_decrypt(e.snapshot_enc) -> 'messages'
            FROM public.dating_report_evidence AS e WHERE e.report_id = p_report);
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. The console's reads.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.moderation_whoami(p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'role', v_mod.role,
    'sensitive_routing_allowed', v_mod.sensitive_routing_allowed, 'languages', to_jsonb(v_mod.languages));
END;
$$;

-- Open cases by priority and time to their clock; a case needing routing
-- only for those allowed (decided now, never stored).
-- Task 5: VOLATILE, a read that counts not_moderator (a write).
CREATE OR REPLACE FUNCTION public.moderation_queue(p_actor uuid, p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'cases', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'id', c.id, 'kind', c.kind, 'priority', c.priority, 'state', c.state, 'signal_kind', c.signal_kind,
             'category', (SELECT r.category FROM public.dating_reports AS r WHERE r.case_id = c.id
                           ORDER BY r.priority, r.created_at LIMIT 1),
             'reports', (SELECT count(*) FROM public.dating_reports AS r WHERE r.case_id = c.id),
             'sla_due_at', c.sla_due_at, 'created_at', c.created_at,
             'mine', c.assigned_to = p_actor, 'claimed', c.assigned_to IS NOT NULL,
             'gone', c.target_user_id IS NULL)
           ORDER BY c.priority, c.sla_due_at NULLS LAST, c.created_at)
      FROM (SELECT x.* FROM public.dating_moderation_cases AS x
             WHERE x.state IN ('open', 'in_review')
               AND NOT private.dating_case_party(v_mod.user_id, x.id) -- Task 5 fix round 1 (I-2)
               AND (v_mod.sensitive_routing_allowed OR NOT private.dating_case_needs_sensitive_routing(x.id))
             ORDER BY x.priority, x.sla_due_at NULLS LAST, x.created_at
             LIMIT greatest(1, least(coalesce(p_limit, 50), 200))) AS c), '[]'::jsonb));
END;
$$;

-- One case: what §6.4 lists, never the reporter's identity, never a
-- special-category answer (no function here reads one), never CSAM.
CREATE OR REPLACE FUNCTION public.moderation_case(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
    'case', pg_catalog.jsonb_build_object('id', c.id, 'kind', c.kind, 'priority', c.priority, 'state', c.state,
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
                          FROM public.dating_reports AS r WHERE r.case_id = c.id OR r.id = c.report_id), '[]'::jsonb),
    'profile', v_profile,
    -- Task 5 (S-5): without routing, an earlier case carries no id: one that
    -- needs routing would read case_unavailable when opened, and so say
    -- what routing knows. Every earlier case is still listed (the history).
    'prior', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('kind', x.kind,
                         'state', x.state, 'outcome', x.outcome, 'created_at', x.created_at)
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
$$;

-- ---------------------------------------------------------------------
-- 4. The console's actions. Each: the moderator, the case they may see
--    (else case_unavailable), one audit row; the detail holds fixed keys
--    only (never routing, never a special-category value). Task 5: a
--    write takes the person's setup lock, then the case row
--    (dating_case_lock); a replay answers as the first call did and writes
--    no second row (M-11).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.moderation_claim(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Task 5 fix round 1 (M-3)
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v_took boolean := false;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- Task 5 fix round 1 (M-3): a lock not had in 2 s answers busy (counted)
    c := private.dating_case_lock(v_mod, p_case);
    IF c.id IS NULL OR c.state NOT IN ('open', 'in_review') THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    IF c.state = 'in_review' AND c.assigned_to = p_actor AND private.dating_moderation_replayed(p_actor, c.id, 'claim') THEN
      RETURN pg_catalog.jsonb_build_object('ok', true); -- Task 5 (M-11): a replay
    END IF;
    -- Fix round 1 (M-5): another moderator's live claim (an action of theirs
    -- on the case in the last hour) is taken over only by the safety owner;
    -- a take-over is audited and the answer says so.
    IF c.assigned_to IS NOT NULL AND c.assigned_to <> p_actor THEN
      IF v_mod.role <> 'safety_owner'
         AND EXISTS (SELECT 1 FROM public.dating_moderation_actions AS a
                      WHERE a.case_id = c.id AND a.actor_id = c.assigned_to AND a.created_at > now() - interval '1 hour') THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'claimed');
      END IF;
      v_took := true;
    END IF;
    UPDATE public.dating_moderation_cases AS x SET assigned_to = p_actor, state = 'in_review' WHERE x.id = c.id;
    PERFORM private.dating_audit(p_actor, c.id, 'claim', c.target_user_id,
                                 CASE WHEN v_took THEN '{"took_over": true}'::jsonb ELSE '{}'::jsonb END);
    RETURN pg_catalog.jsonb_build_object('ok', true)
           || CASE WHEN v_took THEN '{"took_over": true}'::jsonb ELSE '{}'::jsonb END;
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- The interim holds a case placed are lifted with its decision. Fix round
-- 1 (C-1): every hold of the case, whoever placed it (a report, a
-- moderator, a carried record), keyed to the case; a report's age check
-- too. A CSAM hold is never lifted here (Spec 1's path clears it).
CREATE OR REPLACE FUNCTION private.dating_lift_case_holds(p_case uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.dating_account_restrictions AS r SET lifted_at = now()
   WHERE r.case_id = p_case AND r.lifted_at IS NULL
     AND ((r.restriction_type = 'moderation_hold' AND r.source <> 'csam_hash')
          OR (r.restriction_type = 'age_review' AND r.source = 'report'));
$$;

-- Dismiss: no action (a signal case's dismissal lifts its throttle: the
-- close stamps decided_at, which the cleared-signal filter reads, W6 T5).
CREATE OR REPLACE FUNCTION public.moderation_dismiss(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Task 5 fix round 1 (M-3)
AS $$
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
    IF c.id IS NULL OR c.kind = 'appeal' THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    IF c.outcome = 'dismissed' AND private.dating_moderation_replayed(p_actor, c.id, 'dismiss') THEN
      RETURN pg_catalog.jsonb_build_object('ok', true); -- Task 5 (M-11): a replay
    END IF;
    v := private.dating_close_case(c.id, p_actor, 'dismissed');
    IF (v ->> 'ok')::boolean THEN
      PERFORM private.dating_lift_case_holds(c.id);
      PERFORM private.dating_audit(p_actor, c.id, 'dismiss', c.target_user_id);
    END IF;
    RETURN v;
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- Hold: an interim hold by a person (not appealable until decided).
CREATE OR REPLACE FUNCTION public.moderation_place_hold(p_actor uuid, p_case uuid, p_category text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Task 5 fix round 1 (M-3)
AS $$
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
       OR c.kind = 'appeal' THEN -- fix round 1 (M-4): an appeal case holds nobody
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
$$;

CREATE OR REPLACE FUNCTION public.moderation_lift_hold(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Task 5 fix round 1 (M-3)
AS $$
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
    UPDATE public.dating_account_restrictions AS r SET lifted_at = now()
     WHERE r.user_id = c.target_user_id AND r.restriction_type IN ('moderation_hold', 'age_review') AND r.lifted_at IS NULL
       AND r.case_id = c.id AND r.source <> 'csam_hash';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_rows := (SELECT count(*) FROM public.dating_account_restrictions AS r WHERE r.case_id = c.id);
    IF v_n = 0 THEN
      -- Task 5 (M-11): nothing left to lift after this moderator's own lift,
      -- and nothing placed on the case since (fix round 1, M-6): a replay,
      -- answered with the first count.
      SELECT a.detail INTO v_first FROM public.dating_moderation_actions AS a
       WHERE a.actor_id = p_actor AND a.case_id = c.id AND a.action = 'lift_hold'
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
$$;

-- Restrict (§6.3): suspended (until a date, or for good) or a closer look
-- (under_review); the case's interim holds go; the case is decided. Task 5:
-- the case is decided first (the one gate: a case decided meanwhile, or a
-- replay, places nothing).
CREATE OR REPLACE FUNCTION public.moderation_restrict(p_actor uuid, p_case uuid, p_type text, p_ends_at timestamptz,
                                                      p_category text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Task 5 fix round 1 (M-3)
AS $$
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
    IF c.id IS NULL OR c.target_user_id IS NULL OR c.kind = 'appeal' THEN
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
$$;

-- Ask for ID: the person's Dating waits for an ID check (an age review);
-- the case is decided.
CREATE OR REPLACE FUNCTION public.moderation_ask_for_id(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Task 5 fix round 1 (M-3)
AS $$
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
    IF c.id IS NULL OR c.target_user_id IS NULL OR c.kind = 'appeal' THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    IF c.outcome = 'asked_for_id' AND private.dating_moderation_replayed(p_actor, c.id, 'ask_for_id') THEN
      RETURN pg_catalog.jsonb_build_object('ok', true); -- Task 5 (M-11): a replay
    END IF;
    IF c.state NOT IN ('open', 'in_review') THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    v := private.dating_close_case(c.id, p_actor, 'asked_for_id');
    IF NOT (v ->> 'ok')::boolean THEN
      RETURN v;
    END IF;
    PERFORM private.dating_lift_case_holds(c.id); -- fix round 1 (C-1): the case's interim holds go with it
    PERFORM private.dating_place_restriction(c.target_user_id, 'age_review', 'underage_risk', 'moderator', c.id, p_actor,
                                             NULL, false);
    PERFORM private.dating_audit(p_actor, c.id, 'ask_for_id', c.target_user_id);
    RETURN pg_catalog.jsonb_build_object('ok', true);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- §6.3: a moderator confirms a minor on an underage_risk case: Spec 1's
-- account-level age review (three arguments, I-7) closes the whole app.
CREATE OR REPLACE FUNCTION public.moderation_confirm_minor(p_actor uuid, p_case uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Task 5 fix round 1 (M-3)
AS $$
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
    IF c.id IS NULL OR c.state NOT IN ('open', 'in_review') OR c.target_user_id IS NULL
       OR NOT EXISTS (SELECT 1 FROM public.dating_reports AS r WHERE r.case_id = c.id AND r.category = 'underage_risk') THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    v := private.dating_close_case(c.id, p_actor, 'restricted');
    IF NOT (v ->> 'ok')::boolean THEN
      RETURN v;
    END IF;
    PERFORM private.dating_lift_case_holds(c.id); -- fix round 1 (C-1): the case's interim holds go with it
    PERFORM private.dating_place_restriction(c.target_user_id, 'age_review', 'underage_risk', 'moderator', c.id, p_actor,
                                             NULL, false);
    PERFORM public.place_account_hold(c.target_user_id, 'age_review', c.id::text);
    PERFORM private.dating_audit(p_actor, c.id, 'confirm_minor', c.target_user_id);
    RETURN pg_catalog.jsonb_build_object('ok', true);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_note(p_actor uuid, p_case uuid, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Task 5 fix round 1 (M-3)
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  c public.dating_moderation_cases;
  v_note constant text := NULLIF(btrim(coalesce(p_note, '')), '');
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- Task 5 fix round 1 (M-3): a lock not had in 2 s answers busy (counted)
    IF v_note IS NULL OR char_length(v_note) > 1000 THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
    END IF;
    c := private.dating_case_lock(v_mod, p_case);
    IF c.id IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    IF private.dating_moderation_replayed(p_actor, c.id, 'note', pg_catalog.jsonb_build_object('note', v_note)) THEN
      RETURN pg_catalog.jsonb_build_object('ok', true); -- Task 5 (M-11): the same note again is a replay
    END IF;
    PERFORM private.dating_audit(p_actor, c.id, 'note', c.target_user_id, pg_catalog.jsonb_build_object('note', v_note));
    RETURN pg_catalog.jsonb_build_object('ok', true);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- Appeals (§6.3): W7a's rule decides who may (mutant 15). Task 5: a
-- replay (this moderator already decided it this way) answers ok, not
-- W7a's appeal_unavailable (M-11); a restriction nobody is recorded as
-- deciding answers decider_unknown, not same_decider (R1-3: only the
-- safety owner decides its appeal, 24 hours after it was sent).
CREATE OR REPLACE FUNCTION public.moderation_decide_appeal(p_actor uuid, p_case uuid, p_accept boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Task 5 fix round 1 (M-3)
AS $$
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
    IF c.id IS NULL OR c.kind <> 'appeal' OR c.appeal_id IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'case_unavailable');
    END IF;
    IF p_accept IS NOT NULL AND EXISTS (SELECT 1 FROM public.dating_appeals AS a
                                         WHERE a.id = c.appeal_id AND a.decided_by = p_actor
                                           AND a.state = CASE WHEN p_accept THEN 'accepted' ELSE 'rejected' END) THEN
      RETURN pg_catalog.jsonb_build_object('ok', true); -- Task 5 (M-11): a replay
    END IF;
    v := private.dating_decide_appeal(c.appeal_id, p_actor, v_mod.role = 'safety_owner', p_accept);
    IF v ->> 'reason' = 'same_decider'
       AND EXISTS (SELECT 1 FROM public.dating_appeals AS a JOIN public.dating_account_restrictions AS r ON r.id = a.restriction_id
                    WHERE a.id = c.appeal_id AND r.decided_by IS NULL) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'decider_unknown'); -- Task 5 (R1-3)
    END IF;
    IF (v ->> 'ok')::boolean THEN
      IF p_accept THEN -- fix round 1 (C-1): an accepted appeal ends its case's holds too
        PERFORM private.dating_lift_case_holds(r.case_id)
           FROM public.dating_appeals AS a JOIN public.dating_account_restrictions AS r ON r.id = a.restriction_id
          WHERE a.id = c.appeal_id AND r.case_id IS NOT NULL;
      END IF;
      PERFORM private.dating_audit(p_actor, c.id, 'decide_appeal', c.target_user_id,
                                   pg_catalog.jsonb_build_object('accept', p_accept));
    END IF;
    RETURN v;
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- Photos waiting for a person (§6.4): approve, or reject with a reason.
-- Task 5: VOLATILE, a read that counts not_moderator (a write).
CREATE OR REPLACE FUNCTION public.moderation_photos(p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'photos', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', f.id, 'position', f.position, 'key', f.storage_key,
             'reason', f.rejection_reason, 'created_at', f.created_at) ORDER BY f.created_at)
      FROM public.dating_profile_photos AS f
     WHERE f.moderation_state = 'needs_review' AND f.csam_state = 'clear'
       AND f.user_id <> p_actor), '[]'::jsonb)); -- Task 5 fix round 1 (I-2): never one's own
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_photo_decide(p_actor uuid, p_photo uuid, p_approve boolean, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Task 5 fix round 1 (M-3)
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v_user uuid;
  v_owner uuid;
  v_detail jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- Task 5 fix round 1 (M-3): a lock not had in 2 s answers busy (counted)
    IF p_approve IS NULL OR (NOT p_approve AND (p_reason IS NULL OR p_reason NOT IN ('face_unclear', 'too_small', 'contains_child', 'unsafe'))) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
    END IF;
    v_detail := pg_catalog.jsonb_build_object('photo', p_photo, 'approve', p_approve,
                                              'reason', CASE WHEN p_approve THEN NULL ELSE p_reason END);
    -- Task 5 (W7a M-11): the owner's setup lock before the photo row (W3's
    -- photo writers' order).
    SELECT f.user_id INTO v_owner FROM public.dating_profile_photos AS f WHERE f.id = p_photo;
    IF v_owner = p_actor THEN -- fix round 1 (I-2): never one's own photo
      PERFORM private.bump_metric_internal('dating.moderation.party_refused');
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'photo_unavailable');
    END IF;
    IF v_owner IS NOT NULL THEN
      PERFORM private.dating_lock_setup(v_owner);
    END IF;
    UPDATE public.dating_profile_photos AS f
       SET moderation_state = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
           rejection_reason = CASE WHEN p_approve THEN NULL ELSE p_reason END
     WHERE f.id = p_photo AND f.moderation_state = 'needs_review' AND f.csam_state = 'clear'
    RETURNING f.user_id INTO v_user;
    IF v_user IS NULL THEN
      IF private.dating_moderation_replayed(p_actor, NULL, 'photo_decide', v_detail) THEN
        RETURN pg_catalog.jsonb_build_object('ok', true); -- Task 5 (M-11): a replay
      END IF;
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'photo_unavailable');
    END IF;
    PERFORM private.dating_audit(p_actor, NULL, 'photo_decide', v_user, v_detail);
    RETURN pg_catalog.jsonb_build_object('ok', true);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- Verifications waiting for a person (§6.4): the gesture photos' paths
-- (the edge function signs them) beside the approved photos.
-- Task 5: VOLATILE, a read that counts not_moderator (a write).
CREATE OR REPLACE FUNCTION public.moderation_verifications(p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'sessions', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', s.id, 'step', s.step, 'kind', s.kind,
             'gestures', to_jsonb(s.gestures), 'since', coalesce(s.awaiting_since, s.updated_at),
             'review_paths', CASE WHEN s.step = 'human' THEN pg_catalog.jsonb_build_array(s.id || '/1.jpg', s.id || '/2.jpg')
                                  ELSE '[]'::jsonb END,
             'photos', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('position', f.position, 'key', f.storage_key)
                                          ORDER BY f.position)
                                   FROM public.dating_profile_photos AS f
                                  WHERE f.user_id = s.user_id AND f.moderation_state = 'approved' AND f.csam_state = 'clear'),
                                '[]'::jsonb)) ORDER BY coalesce(s.awaiting_since, s.updated_at))
      FROM public.dating_verification_sessions AS s WHERE s.state = 'awaiting_review'
       AND s.user_id <> p_actor), '[]'::jsonb)); -- Task 5 fix round 1 (I-2): never one's own
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_verification_decide(p_actor uuid, p_session uuid, p_outcome text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Task 5 fix round 1 (M-3)
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v_user uuid;
  v jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- Task 5 fix round 1 (M-3): a lock not had in 2 s answers busy (counted)
    SELECT s.user_id INTO v_user FROM public.dating_verification_sessions AS s WHERE s.id = p_session;
    IF v_user = p_actor THEN -- fix round 1 (I-2): never one's own check
      PERFORM private.bump_metric_internal('dating.moderation.party_refused');
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'session_unavailable');
    END IF;
    v := public.decide_dating_human_review(p_session, p_outcome, p_actor);
    IF v ->> 'reason' = 'session_unavailable' AND p_session IS NOT NULL
       AND private.dating_moderation_replayed(p_actor, NULL, 'verification_decide',
                                              pg_catalog.jsonb_build_object('session', p_session, 'outcome', p_outcome)) THEN
      RETURN pg_catalog.jsonb_build_object('ok', true); -- Task 5 (M-11): a replay
    END IF;
    IF (v ->> 'ok')::boolean THEN
      PERFORM private.dating_audit(p_actor, NULL, 'verification_decide', v_user,
                                   pg_catalog.jsonb_build_object('session', p_session, 'outcome', p_outcome));
    END IF;
    RETURN v;
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- Countries (§6.4): the current rows; publishing is the safety owner's.
-- Task 5: VOLATILE, a read that counts not_moderator (a write).
CREATE OR REPLACE FUNCTION public.moderation_countries(p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'countries', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('country', c.country_code, 'version', c.version, 'tier', c.tier,
             'dating_enabled', c.dating_enabled, 'same_gender_enabled', c.same_gender_enabled,
             'open_regions', to_jsonb(c.open_regions), 'published_at', c.published_at) ORDER BY c.country_code)
      FROM public.country_safety_config AS c WHERE c.is_current), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_publish_country(p_actor uuid, p_country text, p_values jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Task 5 fix round 1 (M-3)
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v jsonb;
  v_cur public.country_safety_config;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- Task 5 fix round 1 (M-3): a lock not had in 2 s answers busy (counted)
    IF v_mod.role <> 'safety_owner' THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
    END IF;
    -- Fix round 1 (M-3): the same values again from this owner, nobody having
    -- published the country since, is a replay: answered from the version
    -- it made (the stable keys), published once.
    SELECT x.* INTO v_cur FROM public.country_safety_config AS x
     WHERE x.country_code = upper(coalesce(p_country, '')) AND x.is_current;
    IF v_cur.version IS NOT NULL
       AND private.dating_moderation_replayed(p_actor, NULL, 'publish_country',
             pg_catalog.jsonb_build_object('country', upper(p_country), 'version', v_cur.version,
                                           'values_md5', pg_catalog.md5(coalesce(p_values, 'null'::jsonb)::text))) THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'country', v_cur.country_code, 'version', v_cur.version,
                                           'dating_enabled', v_cur.dating_enabled, 'same_gender_enabled', v_cur.same_gender_enabled,
                                           'environment', private.attune_environment());
    END IF;
    v := public.publish_country_config(p_country, p_values);
    IF (v ->> 'ok')::boolean THEN
      PERFORM private.dating_audit(p_actor, NULL, 'publish_country', NULL,
                                   pg_catalog.jsonb_build_object('country', upper(p_country), 'version', (v ->> 'version')::int,
                                                                 'values_md5', pg_catalog.md5(coalesce(p_values, 'null'::jsonb)::text)));
    END IF;
    RETURN v;
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- S1 W9b's review queue v0, through its own two RPCs only.
CREATE OR REPLACE FUNCTION public.moderation_opinions_queue(p_actor uuid, p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  PERFORM private.dating_audit(p_actor, NULL, 'opinions_view', NULL);
  RETURN pg_catalog.jsonb_build_object('ok', true, 'reports',
    public.admin_list_priority_reports(greatest(1, least(coalesce(p_limit, 50), 200))));
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_opinions_remove(p_actor uuid, p_type text, p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s' -- Task 5 fix round 1 (M-3)
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator'); -- Task 5: counted on every function
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  BEGIN -- Task 5 fix round 1 (M-3): a lock not had in 2 s answers busy (counted)
    IF p_type IS NULL OR p_type NOT IN ('opinion', 'comment') OR p_id IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
    END IF;
    IF private.dating_moderation_replayed(p_actor, NULL, 'opinions_remove', pg_catalog.jsonb_build_object('type', p_type, 'id', p_id)) THEN
      RETURN pg_catalog.jsonb_build_object('ok', true); -- Task 5 (M-11): a replay (S1 W9b's RPC is not called twice)
    END IF;
    PERFORM public.admin_confirm_content_removal(p_type, p_id);
    PERFORM private.dating_audit(p_actor, NULL, 'opinions_remove', NULL,
                                 pg_catalog.jsonb_build_object('type', p_type, 'id', p_id));
    RETURN pg_catalog.jsonb_build_object('ok', true);
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure THEN
    PERFORM private.bump_metric_internal('dating.moderation.busy');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'busy');
  END;
END;
$$;

-- Task 5: VOLATILE, a read that counts not_moderator (a write). Fix round
-- 1: newest first, a row of a case left out when the case needs routing
-- they lack or they are a party to it, each case judged once (M-8).
CREATE OR REPLACE FUNCTION public.moderation_audit_log(p_actor uuid, p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
$$;

-- ---------------------------------------------------------------------
-- 5. SLA alerts (§4.6, §6.5): every 15 minutes, for each priority with an
--    open case past its clock, one content-free line about the oldest
--    ("P0 case waiting 3 h 40 m"): no id, no name, no category.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.dating_moderation_sla_check(p_now timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_hook constant text := public.app_setting('moderation_alert_webhook');
  r record;
  v_n integer := 0;
  v_mins integer;
BEGIN
  FOR r IN
    SELECT c.priority, min(c.created_at) AS oldest
      FROM public.dating_moderation_cases AS c
     WHERE c.state IN ('open', 'in_review') AND c.sla_due_at < p_now
     GROUP BY c.priority ORDER BY c.priority
  LOOP
    IF v_hook IS NULL THEN
      PERFORM private.bump_metric_internal('dating.sla.alert_unconfigured');
      CONTINUE;
    END IF;
    v_mins := greatest(0, floor(extract(epoch FROM p_now - r.oldest) / 60))::int;
    BEGIN
      PERFORM net.http_post(
        url := v_hook,
        headers := pg_catalog.jsonb_build_object('Content-Type', 'application/json'),
        body := pg_catalog.jsonb_build_object('text',
          r.priority || ' case waiting ' || (v_mins / 60) || ' h ' || (v_mins % 60) || ' m'));
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      PERFORM private.bump_metric_internal('dating.sla.alert_failed');
    END;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('alerts', v_n);
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = 'cron') THEN
    PERFORM cron.unschedule(j.jobid) FROM cron.job AS j WHERE j.jobname = 'dating-moderation-sla';
    PERFORM cron.schedule('dating-moderation-sla', '*/15 * * * *', $c$SELECT public.dating_moderation_sla_check()$c$);
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 6. Self-revoke (the W6 final pattern).
-- ---------------------------------------------------------------------
REVOKE ALL ON TABLE public.dating_moderators, public.dating_moderation_actions FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  private.dating_moderation_actions_guard(), private.dating_audit(uuid, uuid, text, uuid, jsonb),
  private.dating_moderator(uuid), private.dating_identity_of(uuid), private.dating_case_needs_sensitive_routing(uuid),
  private.dating_case_for(public.dating_moderators, uuid), private.dating_evidence_messages(uuid),
  private.dating_lift_case_holds(uuid),
  private.dating_moderation_replayed(uuid, uuid, text, jsonb), private.dating_case_lock(public.dating_moderators, uuid), -- Task 5
  private.dating_case_party(uuid, uuid), -- Task 5 fix round 1
  public.moderation_whoami(uuid), public.moderation_queue(uuid, integer), public.moderation_case(uuid, uuid),
  public.moderation_claim(uuid, uuid), public.moderation_dismiss(uuid, uuid), public.moderation_place_hold(uuid, uuid, text),
  public.moderation_lift_hold(uuid, uuid), public.moderation_restrict(uuid, uuid, text, timestamptz, text),
  public.moderation_ask_for_id(uuid, uuid), public.moderation_confirm_minor(uuid, uuid),
  public.moderation_note(uuid, uuid, text), public.moderation_decide_appeal(uuid, uuid, boolean),
  public.moderation_photos(uuid), public.moderation_photo_decide(uuid, uuid, boolean, text),
  public.moderation_verifications(uuid), public.moderation_verification_decide(uuid, uuid, text),
  public.moderation_countries(uuid), public.moderation_publish_country(uuid, text, jsonb),
  public.moderation_opinions_queue(uuid, integer), public.moderation_opinions_remove(uuid, text, uuid),
  public.moderation_audit_log(uuid, integer), public.dating_moderation_sla_check(timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
