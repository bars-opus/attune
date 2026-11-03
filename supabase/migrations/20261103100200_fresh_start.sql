-- Spec 1 W6a, migration 11 part 3 of 3 (spec §4.7 #11; plan P-1):
-- fresh_start. A recycled number gets a fresh start; the old account is
-- parked for 180 days of support-only recovery, then deleted.
--   * private.fresh_start_attempts: start-fresh-account's per-IP limit (5
--     an hour, spec §4.5), as an HMAC of the address; kept 1 hour.
--   * consume_fresh_start(p_nonce, p_ip_hash) -> uuid (service role): a
--     nonce the hook sealed in the last 15 minutes, for an account still
--     dormant and with no hold, taken once: the challenge is recorded as
--     used, users.parked_phone_hmac is written from the REAL auth.users
--     phone (review I-11) before anything changes the number, a
--     recovery_hold is placed (expires in 180 days) and the account id
--     comes back. The same nonce again returns the same id only while the
--     park isn't finished (phone_released_at unset), so a failed park can
--     be retried; anything else returns NULL (plan P-10: a NULL, not a
--     raise, so the IP attempt it counted is kept). Past the IP limit:
--     fresh_start:try_later.
--   * mark_fresh_start_parked(p_user) (service role): after the Auth number
--     moved to +999, sets users.phone_released_at.
--   * recovery_hold_candidates() / is_recovery_hold_due(p_user) (service
--     role): recovery holds past their 180 days, for purge-recovery-holds;
--     never an account that also has an open age_review or safety_review
--     (batch 2 review M-4 ruling: an expiry purge must never destroy a
--     review; such an account waits until the review is resolved).
--   * identity_alerts_due() / mark_identity_alerts_sent(p_ids) (service
--     role): hook fail-opens not yet posted (review S-8).
--   * private.fresh_starts_unparked() and fresh_start_park_alerts_due() /
--     mark_fresh_start_park_alerts_sent(p_ids) (service role), with
--     private.fresh_start_park_alerts (preflight F4): a fresh start whose
--     park never finished (the hold placed 15+ minutes ago, so the nonce
--     can no longer be retried, and the number never moved) leaves the
--     real number behind a recovery hold, so its new owner sees H1. It is
--     counted in identity health (fresh_starts_unparked) and alerted once
--     per hold; support finishes the park. Ids go to the mark only; the
--     post carries counts and times.
--   * private.parked_kept_for_review() and parked_kept_for_review_alerts_due()
--     / mark_parked_kept_for_review_alerts_sent(p_ids) (service role), with
--     private.parked_review_alerts (batch 3, after the M-4 ruling): a
--     recovery hold past its 180 days that the purge skips because an age
--     or safety review is open. Counted in identity health
--     (parked_kept_for_review) and alerted once per hold, so support
--     resolves the review; the purge then deletes the account.
--   * account_deletion_requests.source (batch 3 fix M-2): nullable;
--     'recovery_purge' on purge-recovery-holds' audit rows, NULL for a
--     person's own deletion (delete-account is unchanged). Grants unchanged.
--   * private.recovery_purge_stuck() and recovery_purge_stuck_alerts_due() /
--     mark_recovery_purge_stuck_alerts_sent(p_ids) (service role), with
--     private.recovery_purge_stuck_alerts (batch 3 fix M-3): a candidate
--     whose purge failed in 3 runs since its hold was placed (3 unfinished
--     recovery_purge rows) goes to the back of recovery_hold_candidates, so
--     it can never block the list, and is counted in identity health
--     (recovery_purge_stuck) and alerted once per hold.
--   * private.identity_health_w6a() and get_identity_health() re-created
--     from its live body (20261025100500) with one change: the W1 object
--     || private.identity_health_w6a(), so the W1 body still names no W6
--     table (identity contract I4; plan P-11).
--   * crons: fresh-start-retention (43 * * * *), purge-recovery-holds
--     (55 3 * * *), identity-health-alert (*/15 * * * *).
--   * fresh_start_key_present is true only for a key the sealer accepts
--     (at least 32 characters; batch 1 review M-2).
-- Grants in 20261103100210_fresh_start_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS private.fresh_start_attempts (
  ip_hash text NOT NULL CONSTRAINT fresh_start_attempts_ip_hash_check CHECK (ip_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS fresh_start_attempts_key_idx ON private.fresh_start_attempts (ip_hash, created_at);

-- Batch 3 fix M-2: who started a deletion. NULL is the person
-- (delete-account); 'recovery_purge' is purge-recovery-holds. Nullable, no
-- default: metadata only, no rewrite.
ALTER TABLE public.account_deletion_requests
  ADD COLUMN IF NOT EXISTS source text
  CONSTRAINT account_deletion_requests_source_check CHECK (source IN ('recovery_purge'));

-- One row per stuck purge already alerted (batch 3 fix M-3), keyed by the
-- hold's placing time.
CREATE TABLE IF NOT EXISTS private.recovery_purge_stuck_alerts (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  hold_created_at timestamptz NOT NULL,
  alerted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, hold_created_at)
);

-- One row per parked account kept for an open review already alerted
-- (batch 3), keyed by the hold's expiry so a hold placed again alerts again.
CREATE TABLE IF NOT EXISTS private.parked_review_alerts (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  hold_expires_at timestamptz NOT NULL,
  alerted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, hold_expires_at)
);

-- One row per stuck park already alerted (preflight F4), keyed by the
-- hold's placing time so a hold placed again alerts again.
CREATE TABLE IF NOT EXISTS private.fresh_start_park_alerts (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  hold_created_at timestamptz NOT NULL,
  alerted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, hold_created_at)
);

CREATE OR REPLACE FUNCTION public.consume_fresh_start(p_nonce text, p_ip_hash text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now constant timestamptz := clock_timestamp();
  v_user uuid;
  v_issued timestamptz;
  v_hash text;
  v_taken public.fresh_start_challenges%ROWTYPE;
  v_created timestamptz;
  v_released timestamptz;
  v_digits text;
BEGIN
  IF p_ip_hash IS NOT NULL THEN
    IF p_ip_hash !~ '^[0-9a-f]{64}$' THEN
      RETURN NULL;
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('fresh-start-ip:' || p_ip_hash, 0));
    IF (SELECT count(*) FROM (SELECT 1 FROM private.fresh_start_attempts AS a
                               WHERE a.ip_hash = p_ip_hash AND a.created_at > v_now - interval '1 hour'
                               LIMIT 5) AS recent) >= 5 THEN
      RAISE EXCEPTION 'fresh_start:try_later';
    END IF;
    INSERT INTO private.fresh_start_attempts (ip_hash, created_at) VALUES (p_ip_hash, v_now);
  END IF;

  SELECT o.user_id, o.issued_at INTO v_user, v_issued FROM private.open_fresh_start(p_nonce) AS o;
  IF v_user IS NULL
     OR v_issued > v_now + interval '1 minute'
     OR v_issued < v_now - interval '15 minutes' THEN
    RETURN NULL;
  END IF;

  -- The users row first (the order set_user_path_internal and the accept
  -- use), so two takes of one nonce serialise here.
  SELECT u.created_at, u.phone_released_at INTO v_created, v_released
    FROM public.users AS u WHERE u.id = v_user FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  v_hash := encode(extensions.digest(p_nonce, 'sha256'), 'hex');
  SELECT * INTO v_taken FROM public.fresh_start_challenges AS c WHERE c.nonce_hash = v_hash;
  IF FOUND THEN
    -- Taken before: only to finish a park that didn't complete.
    IF v_taken.user_id = v_user AND v_released IS NULL
       AND EXISTS (SELECT 1 FROM public.account_holds AS h
                    WHERE h.user_id = v_user AND h.kind = 'recovery_hold' AND h.resolved_at IS NULL) THEN
      RETURN v_user;
    END IF;
    RETURN NULL;
  END IF;

  -- Used again since the challenge (its owner is back), already parked, or
  -- held for any reason: no fresh start.
  IF coalesce((SELECT a.last_active_at FROM public.account_activity AS a WHERE a.user_id = v_user), v_created)
       >= now() - interval '180 days'
     OR v_released IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.account_holds AS h WHERE h.user_id = v_user AND h.resolved_at IS NULL) THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.fresh_start_challenges (nonce_hash, user_id, created_at, used_at)
  VALUES (v_hash, v_user, v_issued, v_now);

  -- I-11: the real number's HMAC, in the form Spec 2's helper reads Auth's
  -- phone ('+' || digits), before start-fresh-account parks it.
  v_digits := nullif(regexp_replace(coalesce((SELECT a.phone FROM auth.users AS a WHERE a.id = v_user), ''), '\D', '', 'g'), '');
  UPDATE public.users AS u
     SET parked_phone_hmac = CASE WHEN v_digits IS NULL THEN NULL ELSE public.dating_phone_hmac('+' || v_digits) END
   WHERE u.id = v_user;
  PERFORM public.place_account_hold(v_user, 'recovery_hold', 'fresh_start');
  PERFORM private.bump_metric_internal('dormancy_fresh_start');
  RETURN v_user;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_fresh_start_parked(p_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.users AS u
     SET phone_released_at = coalesce(u.phone_released_at, now())
   WHERE u.id = p_user
     AND EXISTS (SELECT 1 FROM public.account_holds AS h
                  WHERE h.user_id = p_user AND h.kind = 'recovery_hold' AND h.resolved_at IS NULL)
     AND (SELECT a.phone FROM auth.users AS a WHERE a.id = p_user) ~ '^\+?999[0-9]{12}$';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fresh_start:not_parked';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.recovery_hold_candidates()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  -- Fix M-3: an account whose purge failed in 3 runs since this hold was
  -- placed goes last, so it can never block the head of the list.
  SELECT h.user_id
    FROM public.account_holds AS h
   CROSS JOIN LATERAL (SELECT count(*) AS n FROM (
            SELECT 1 FROM public.account_deletion_requests AS d
             WHERE d.user_ref = h.user_id AND d.source = 'recovery_purge'
               AND d.completed_at IS NULL AND d.requested_at >= h.created_at
             LIMIT 3) AS t) AS f
   WHERE h.kind = 'recovery_hold' AND h.resolved_at IS NULL AND h.expires_at < now()
     AND NOT EXISTS (SELECT 1 FROM public.account_holds AS r
                      WHERE r.user_id = h.user_id AND r.kind IN ('age_review', 'safety_review')
                        AND r.resolved_at IS NULL)
   ORDER BY f.n >= 3, h.expires_at, h.user_id
   LIMIT 200;
$$;

CREATE OR REPLACE FUNCTION public.is_recovery_hold_due(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.account_holds AS h
                  WHERE h.user_id = p_user AND h.kind = 'recovery_hold'
                    AND h.resolved_at IS NULL AND h.expires_at < now())
     AND NOT EXISTS (SELECT 1 FROM public.account_holds AS r
                      WHERE r.user_id = p_user AND r.kind IN ('age_review', 'safety_review')
                        AND r.resolved_at IS NULL);
$$;

CREATE OR REPLACE FUNCTION public.identity_alerts_due()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'ids', coalesce(jsonb_agg(f.id ORDER BY f.id), '[]'::jsonb),
    'count', count(*),
    'first_at', min(f.at),
    'last_at', max(f.at))
    FROM (SELECT x.id, x.at FROM private.auth_hook_failures AS x
           WHERE x.alerted_at IS NULL ORDER BY x.id LIMIT 500) AS f;
$$;

CREATE OR REPLACE FUNCTION public.mark_identity_alerts_sent(p_ids bigint[])
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE private.auth_hook_failures AS f
     SET alerted_at = now()
   WHERE f.id = ANY (coalesce(p_ids, ARRAY[]::bigint[])) AND f.alerted_at IS NULL;
$$;

-- A fresh start whose park never finished (preflight F4): its recovery
-- hold was placed by consume_fresh_start 15+ minutes ago (the nonce can no
-- longer be retried) and the number never moved (phone_released_at unset).
CREATE OR REPLACE FUNCTION private.fresh_starts_unparked()
RETURNS TABLE (user_id uuid, held_since timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT h.user_id, h.created_at
    FROM public.account_holds AS h
    JOIN public.users AS u ON u.id = h.user_id
   WHERE h.kind = 'recovery_hold' AND h.resolved_at IS NULL AND h.reason_ref = 'fresh_start'
     AND u.phone_released_at IS NULL
     AND h.created_at < now() - interval '15 minutes';
$$;

CREATE OR REPLACE FUNCTION public.fresh_start_park_alerts_due()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'ids', coalesce(jsonb_agg(s.user_id ORDER BY s.held_since, s.user_id), '[]'::jsonb),
    'count', count(*),
    'first_at', min(s.held_since),
    'last_at', max(s.held_since))
    FROM (SELECT x.user_id, x.held_since FROM private.fresh_starts_unparked() AS x
           WHERE NOT EXISTS (SELECT 1 FROM private.fresh_start_park_alerts AS a
                              WHERE a.user_id = x.user_id AND a.hold_created_at = x.held_since)
           ORDER BY x.held_since, x.user_id LIMIT 200) AS s;
$$;

CREATE OR REPLACE FUNCTION public.mark_fresh_start_park_alerts_sent(p_ids uuid[])
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO private.fresh_start_park_alerts (user_id, hold_created_at)
  SELECT x.user_id, x.held_since FROM private.fresh_starts_unparked() AS x
   WHERE x.user_id = ANY (coalesce(p_ids, ARRAY[]::uuid[]))
  ON CONFLICT DO NOTHING;
$$;

-- A recovery hold past its 180 days that recovery_hold_candidates skips
-- because an age or safety review is open (M-4 ruling): kept, not purged,
-- until support resolves the review. Exactly the expired recovery holds the
-- candidates leave out.
CREATE OR REPLACE FUNCTION private.parked_kept_for_review()
RETURNS TABLE (user_id uuid, due_since timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT h.user_id, h.expires_at
    FROM public.account_holds AS h
   WHERE h.kind = 'recovery_hold' AND h.resolved_at IS NULL AND h.expires_at < now()
     AND EXISTS (SELECT 1 FROM public.account_holds AS r
                  WHERE r.user_id = h.user_id AND r.kind IN ('age_review', 'safety_review')
                    AND r.resolved_at IS NULL);
$$;

CREATE OR REPLACE FUNCTION public.parked_kept_for_review_alerts_due()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'ids', coalesce(jsonb_agg(s.user_id ORDER BY s.due_since, s.user_id), '[]'::jsonb),
    'count', count(*),
    'first_at', min(s.due_since),
    'last_at', max(s.due_since))
    FROM (SELECT x.user_id, x.due_since FROM private.parked_kept_for_review() AS x
           WHERE NOT EXISTS (SELECT 1 FROM private.parked_review_alerts AS a
                              WHERE a.user_id = x.user_id AND a.hold_expires_at = x.due_since)
           ORDER BY x.due_since, x.user_id LIMIT 200) AS s;
$$;

CREATE OR REPLACE FUNCTION public.mark_parked_kept_for_review_alerts_sent(p_ids uuid[])
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO private.parked_review_alerts (user_id, hold_expires_at)
  SELECT x.user_id, x.due_since FROM private.parked_kept_for_review() AS x
   WHERE x.user_id = ANY (coalesce(p_ids, ARRAY[]::uuid[]))
  ON CONFLICT DO NOTHING;
$$;

-- Fix M-3: a purge candidate (expired, unresolved, no open review) whose
-- purge failed in 3 runs since its hold was placed (3 recovery_purge audit
-- rows never completed).
CREATE OR REPLACE FUNCTION private.recovery_purge_stuck()
RETURNS TABLE (user_id uuid, held_since timestamptz, due_since timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT h.user_id, h.created_at, h.expires_at
    FROM public.account_holds AS h
   WHERE h.kind = 'recovery_hold' AND h.resolved_at IS NULL AND h.expires_at < now()
     AND NOT EXISTS (SELECT 1 FROM public.account_holds AS r
                      WHERE r.user_id = h.user_id AND r.kind IN ('age_review', 'safety_review')
                        AND r.resolved_at IS NULL)
     AND (SELECT count(*) FROM (
            SELECT 1 FROM public.account_deletion_requests AS d
             WHERE d.user_ref = h.user_id AND d.source = 'recovery_purge'
               AND d.completed_at IS NULL AND d.requested_at >= h.created_at
             LIMIT 3) AS t) >= 3;
$$;

CREATE OR REPLACE FUNCTION public.recovery_purge_stuck_alerts_due()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'ids', coalesce(jsonb_agg(s.user_id ORDER BY s.due_since, s.user_id), '[]'::jsonb),
    'count', count(*),
    'first_at', min(s.due_since),
    'last_at', max(s.due_since))
    FROM (SELECT x.user_id, x.due_since FROM private.recovery_purge_stuck() AS x
           WHERE NOT EXISTS (SELECT 1 FROM private.recovery_purge_stuck_alerts AS a
                              WHERE a.user_id = x.user_id AND a.hold_created_at = x.held_since)
           ORDER BY x.due_since, x.user_id LIMIT 200) AS s;
$$;

CREATE OR REPLACE FUNCTION public.mark_recovery_purge_stuck_alerts_sent(p_ids uuid[])
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO private.recovery_purge_stuck_alerts (user_id, hold_created_at)
  SELECT x.user_id, x.held_since FROM private.recovery_purge_stuck() AS x
   WHERE x.user_id = ANY (coalesce(p_ids, ARRAY[]::uuid[]))
  ON CONFLICT DO NOTHING;
$$;

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
    'fresh_start_key_present', coalesce(char_length(public.app_setting('fresh_start_key')), 0) >= 32);
$$;

CREATE OR REPLACE FUNCTION public.get_identity_health()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'accounts_without_birth_date', (
      SELECT count(*) FROM public.users AS u
       WHERE NOT EXISTS (SELECT 1 FROM public.account_birthdates AS b WHERE b.user_id = u.id)),
    'accounts_without_path', (SELECT count(*) FROM public.users AS u WHERE u.path IS NULL),
    'holds', jsonb_build_object(
      'age_review', (SELECT count(*) FROM public.account_holds AS h
                      WHERE h.kind = 'age_review' AND h.resolved_at IS NULL),
      'recovery_hold', (SELECT count(*) FROM public.account_holds AS h
                         WHERE h.kind = 'recovery_hold' AND h.resolved_at IS NULL),
      'safety_review', (SELECT count(*) FROM public.account_holds AS h
                         WHERE h.kind = 'safety_review' AND h.resolved_at IS NULL)),
    'unfinished_signups_awaiting_purge', (SELECT count(*) FROM private.unfinished_signups AS s))
    || private.identity_health_w6a();
$$;

-- Retention (spec §4.6, §4.8): challenges and IP attempts 1 hour, hook
-- fail-opens 30 days, park-alert and kept-for-review marks 181 days (past
-- any recovery hold; a purged account's go with it; an account still kept
-- after that is alerted again). Names only W6a tables.
CREATE OR REPLACE FUNCTION private.fresh_start_retention()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  DELETE FROM public.fresh_start_challenges WHERE created_at < clock_timestamp() - interval '1 hour';
  DELETE FROM private.fresh_start_attempts WHERE created_at < clock_timestamp() - interval '1 hour';
  DELETE FROM private.auth_hook_failures WHERE at < clock_timestamp() - interval '30 days';
  DELETE FROM private.fresh_start_park_alerts WHERE alerted_at < clock_timestamp() - interval '181 days';
  DELETE FROM private.parked_review_alerts WHERE alerted_at < clock_timestamp() - interval '181 days';
  DELETE FROM private.recovery_purge_stuck_alerts WHERE alerted_at < clock_timestamp() - interval '181 days';
$$;

REVOKE ALL ON private.fresh_start_attempts FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON private.fresh_start_park_alerts FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fresh_starts_unparked() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fresh_start_park_alerts_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_fresh_start_park_alerts_sent(uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON private.parked_review_alerts FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.parked_kept_for_review() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.parked_kept_for_review_alerts_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_parked_kept_for_review_alerts_sent(uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON private.recovery_purge_stuck_alerts FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.recovery_purge_stuck() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.recovery_purge_stuck_alerts_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_recovery_purge_stuck_alerts_sent(uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.consume_fresh_start(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_fresh_start_parked(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.recovery_hold_candidates() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.is_recovery_hold_due(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.identity_alerts_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_identity_alerts_sent(bigint[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.identity_health_w6a() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_identity_health() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fresh_start_retention() FROM PUBLIC, anon, authenticated, service_role;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job
   WHERE jobname IN ('fresh-start-retention', 'purge-recovery-holds', 'identity-health-alert');
END;
$$;
SELECT cron.schedule('fresh-start-retention', '43 * * * *', $cron$SELECT private.fresh_start_retention()$cron$);
SELECT cron.schedule('purge-recovery-holds', '55 3 * * *',
                     $cron$SELECT public.invoke_edge_function('purge-recovery-holds')$cron$);
SELECT cron.schedule('identity-health-alert', '*/15 * * * *',
                     $cron$SELECT public.invoke_edge_function('identity-health-alert')$cron$);

COMMIT;
