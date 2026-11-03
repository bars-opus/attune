-- Spec 1 W6c, migration 13 (spec §4.7 #13): child_safety_reports.
--   * public.child_safety_reports (spec §4.2): what a person saw and where,
--     written only by report_child_safety_concern; read only by the named
--     child-safety contact (service role). There is no column for the
--     reported person: nothing can tell them (§3.15). alerted_at (plan
--     P-24) marks a report the safety webhook has been told about (a count
--     and a time, never the words).
--   * report_child_safety_concern(p_where, p_details) (authenticated): 5 a
--     person a day (child_report:limit), the details trimmed and 1-2,000
--     characters (child_report:invalid), where one of chat, stories,
--     opinions, dating, other or none. Sends nothing to anyone.
--   * child_safety_alerts_due() / mark_child_safety_alerts_sent(p_ids)
--     (service role): new reports for identity-health-alert's webhook post
--     (plan P-24).
--   * private.identity_health_w6a() re-created with one more key,
--     child_safety_reports_unalerted: reports still unalerted 15 minutes
--     after they came in (batch 8 fix round 1 ruling), so get_identity_health
--     shows them even with SAFETY_ALERT_WEBHOOK unset.
-- No retention job: how long reports are kept after closing is privacy
-- counsel's call (spec §4.8, §10; plan P-25).
-- Grants in 20261103120010_child_safety_reports_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.child_safety_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  where_seen text
    CONSTRAINT child_safety_reports_where_seen_check
    CHECK (where_seen IN ('chat', 'stories', 'opinions', 'dating', 'other')),
  details text NOT NULL
    CONSTRAINT child_safety_reports_details_check CHECK (char_length(details) BETWEEN 1 AND 2000),
  status text NOT NULL DEFAULT 'new'
    CONSTRAINT child_safety_reports_status_check CHECK (status IN ('new', 'reviewing', 'actioned', 'closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  alerted_at timestamptz
);
CREATE INDEX IF NOT EXISTS child_safety_reports_reporter_idx
  ON public.child_safety_reports (reporter_user_id, created_at);
CREATE INDEX IF NOT EXISTS child_safety_reports_unalerted_idx
  ON public.child_safety_reports (created_at) WHERE alerted_at IS NULL;
ALTER TABLE public.child_safety_reports ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.report_child_safety_concern(p_where text, p_details text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  -- Every kind of blank at either end, newlines and tabs too (fix round 1,
  -- review M-1): a report of only blanks is refused.
  v_details constant text := regexp_replace(coalesce(p_details, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'child_report:not_signed_in';
  END IF;
  IF char_length(v_details) NOT BETWEEN 1 AND 2000
     OR (p_where IS NOT NULL AND p_where NOT IN ('chat', 'stories', 'opinions', 'dating', 'other')) THEN
    RAISE EXCEPTION 'child_report:invalid';
  END IF;
  -- One count at a time per person, so two quick sends can't both be the 5th.
  PERFORM pg_advisory_xact_lock(hashtextextended('child-report:' || v_uid::text, 0));
  IF (SELECT count(*) FROM public.child_safety_reports AS r
       WHERE r.reporter_user_id = v_uid AND r.created_at > now() - interval '1 day') >= 5 THEN
    RAISE EXCEPTION 'child_report:limit';
  END IF;
  INSERT INTO public.child_safety_reports (reporter_user_id, where_seen, details)
  VALUES (v_uid, p_where, v_details);
END;
$$;

CREATE OR REPLACE FUNCTION public.child_safety_alerts_due()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'ids', coalesce(jsonb_agg(r.id ORDER BY r.created_at, r.id), '[]'::jsonb),
    'count', count(*),
    'first_at', min(r.created_at),
    'last_at', max(r.created_at))
    FROM (SELECT x.id, x.created_at FROM public.child_safety_reports AS x
           WHERE x.alerted_at IS NULL ORDER BY x.created_at, x.id LIMIT 500) AS r;
$$;

CREATE OR REPLACE FUNCTION public.mark_child_safety_alerts_sent(p_ids uuid[])
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.child_safety_reports AS r
     SET alerted_at = now()
   WHERE r.id = ANY (coalesce(p_ids, ARRAY[]::uuid[])) AND r.alerted_at IS NULL;
$$;

-- Identity health (batch 8 fix round 1 ruling): private.identity_health_w6a()
-- re-created from its live body (20261103100200_fresh_start.sql) with one
-- key added, child_safety_reports_unalerted. get_identity_health is not
-- touched (it already ends || private.identity_health_w6a()).
CREATE OR REPLACE FUNCTION private.identity_health_w6a()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    -- Taken challenges (the hook's refusals can't be counted: Auth rolls
    -- the refused token's transaction back; plan P-2).
    'fresh_starts_7d', (SELECT coalesce(sum(m.count), 0) FROM public.metric_counters AS m
                         WHERE m.key = 'dormancy_fresh_start' AND m.day > (now() AT TIME ZONE 'utc')::date - 7),
    'parked_accounts', (SELECT count(*) FROM public.account_holds AS h
                         WHERE h.kind = 'recovery_hold' AND h.resolved_at IS NULL),
    'parked_without_hmac', (SELECT count(*) FROM public.account_holds AS h
                              JOIN public.users AS u ON u.id = h.user_id
                             WHERE h.kind = 'recovery_hold' AND h.resolved_at IS NULL
                               AND u.parked_phone_hmac IS NULL),
    'hook_fail_opens_24h', (SELECT count(*) FROM private.auth_hook_failures AS f
                             WHERE f.at > now() - interval '24 hours'),
    'hook_fail_opens_unalerted', (SELECT count(*) FROM private.auth_hook_failures AS f
                                   WHERE f.alerted_at IS NULL),
    'fresh_starts_unparked', (SELECT count(*) FROM private.fresh_starts_unparked()),
    -- Batch 3 (M-4 ruling): past 180 days, kept for an open review.
    'parked_kept_for_review', (SELECT count(*) FROM private.parked_kept_for_review()),
    -- Fix M-3: purge failed in 3 runs, moved to the back of the list.
    'recovery_purge_stuck', (SELECT count(*) FROM private.recovery_purge_stuck()),
    -- The rule private.fresh_start_key applies (batch 1 review M-2).
    'fresh_start_key_present', coalesce(char_length(public.app_setting('fresh_start_key')), 0) >= 32,
    -- W6c (batch 8 fix round 1 ruling): child-safety reports the safety
    -- webhook hasn't been told about 15 minutes after they came in (the
    -- cron runs every 15), so the team sees them even with no webhook set.
    'child_safety_reports_unalerted', (SELECT count(*) FROM public.child_safety_reports AS r
                                        WHERE r.alerted_at IS NULL
                                          AND r.created_at < now() - interval '15 minutes'));
$$;

REVOKE ALL ON public.child_safety_reports FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.report_child_safety_concern(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.child_safety_alerts_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_child_safety_alerts_sent(uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.identity_health_w6a() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
