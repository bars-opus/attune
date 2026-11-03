-- Spec 1 W6a, migration 11 part 2 of 3 (spec §4.7 #11; plan P-1):
-- access_token_hook. Holds start to bite.
--   * users.parked_phone_hmac (review I-11): written by consume_fresh_start
--     (part 3) from the real number before the number is parked. Never
--     granted to clients.
--   * account_activity: the last time the account got a token, written by
--     the hook at most every 12 hours; seeded here from Auth's own sign-in
--     and session times, so no account in use reads as dormant on the
--     day the hook is switched on (plan P-9).
--   * fresh_start_challenges: one row per challenge taken by
--     consume_fresh_start (part 3); kept 1 hour by fresh-start-retention.
--   * private.auth_hook_failures (review S-8): one row per fail-open (no
--     user id, no claims); kept 30 days; alerted by identity-health-alert.
--   * private.seal_fresh_start / private.open_fresh_start: the dormancy
--     challenge is SEALED, not stored (plan P-2). Supabase Auth runs the
--     hook inside the token's own transaction and rolls it back when the
--     hook refuses, so a row the hook inserted on a refusal would never
--     exist. The nonce is AES-256-CBC(user id, issue time) under the Vault
--     secret fresh_start_key, with a 16-byte HMAC-SHA-256 tag: 128 hex
--     characters that say nothing about the old account.
--   * private.access_token_refusal(event): the decision (spec §4.4): any
--     unresolved hold -> account_review (account_review:age for an age
--     hold, plan P-5, except a code sign-in to an age-held account idle
--     180 days: plain account_review, final review I-1); dormancy_rule on, an OTP sign-in, a users row, no
--     activity for 180 days -> account_dormant:<nonce>; otherwise the
--     activity is refreshed (at most every 12 hours) and NULL comes back.
--   * public.attune_access_token_hook(event): Supabase's Custom Access
--     Token Hook. Any unexpected error, a statement timeout included,
--     returns the event unchanged (fail open, R12) and records one
--     auth_hook_failures row and the auth_hook_fail_open metric in its own
--     nested block. Executable by supabase_auth_admin only.
-- Grants in 20261103100110_access_token_hook_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS parked_phone_hmac text;
COMMENT ON COLUMN public.users.parked_phone_hmac IS
  'Spec 1 W6a (review I-11): dating_phone_hmac of the real number, written by consume_fresh_start just before the number is parked on +999. Spec 2''s dating_phone_hmac_for_user prefers it for a parked account. Not granted to clients.';

CREATE TABLE IF NOT EXISTS public.account_activity (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  last_active_at timestamptz NOT NULL
);
ALTER TABLE public.account_activity ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.fresh_start_challenges (
  nonce_hash text PRIMARY KEY
    CONSTRAINT fresh_start_challenges_nonce_hash_check CHECK (nonce_hash ~ '^[0-9a-f]{64}$'),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL,
  used_at timestamptz
);
CREATE INDEX IF NOT EXISTS fresh_start_challenges_created_idx ON public.fresh_start_challenges (created_at);
CREATE INDEX IF NOT EXISTS fresh_start_challenges_user_idx ON public.fresh_start_challenges (user_id);
ALTER TABLE public.fresh_start_challenges ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS private.auth_hook_failures (
  id bigserial PRIMARY KEY,
  at timestamptz NOT NULL DEFAULT clock_timestamp(),
  sqlstate text,
  alerted_at timestamptz
);
CREATE INDEX IF NOT EXISTS auth_hook_failures_unalerted_idx
  ON private.auth_hook_failures (id) WHERE alerted_at IS NULL;
CREATE INDEX IF NOT EXISTS auth_hook_failures_at_idx ON private.auth_hook_failures (at);

-- Seed (plan P-9): the latest of the account's creation, Auth's last
-- sign-in and update, and its sessions' last refresh. Never moves a later
-- value back.
INSERT INTO public.account_activity AS a (user_id, last_active_at)
SELECT u.id,
       greatest(u.created_at, au.last_sign_in_at, au.updated_at,
                (SELECT max(greatest(s.updated_at, s.refreshed_at AT TIME ZONE 'utc'))
                   FROM auth.sessions AS s WHERE s.user_id = u.id))
  FROM public.users AS u
  LEFT JOIN auth.users AS au ON au.id = u.id
ON CONFLICT (user_id) DO UPDATE
  SET last_active_at = greatest(a.last_active_at, EXCLUDED.last_active_at);

-- The two keys, derived from one Vault secret (fresh_start_key, at least
-- 32 characters). Unset: fresh_start:not_configured.
CREATE OR REPLACE FUNCTION private.fresh_start_key(p_purpose text)
RETURNS bytea
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_secret constant text := public.app_setting('fresh_start_key');
BEGIN
  IF v_secret IS NULL OR char_length(v_secret) < 32 THEN
    RAISE EXCEPTION 'fresh_start:not_configured';
  END IF;
  RETURN extensions.digest(p_purpose || ':' || v_secret, 'sha256');
END;
$$;

-- iv (16) || AES-256-CBC(user id (16) || issue time, epoch seconds (8))
-- (32) || HMAC-SHA-256 tag, first 16 bytes; as hex.
CREATE OR REPLACE FUNCTION private.seal_fresh_start(p_user uuid, p_at timestamptz)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_iv constant bytea := extensions.gen_random_bytes(16);
  v_plain constant bytea := decode(replace(p_user::text, '-', ''), 'hex')
                            || int8send(floor(extract(epoch FROM p_at))::bigint);
  v_box bytea;
BEGIN
  v_box := v_iv || extensions.encrypt_iv(v_plain, private.fresh_start_key('enc'), v_iv, 'aes-cbc/pad:pkcs');
  RETURN encode(v_box || substring(extensions.hmac(v_box, private.fresh_start_key('mac'), 'sha256') FROM 1 FOR 16), 'hex');
END;
$$;

-- The account and issue time a nonce was sealed for, or (NULL, NULL) for
-- anything that isn't a nonce this project sealed.
CREATE OR REPLACE FUNCTION private.open_fresh_start(p_nonce text, OUT user_id uuid, OUT issued_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_raw bytea;
  v_plain bytea;
BEGIN
  IF p_nonce IS NULL OR p_nonce !~ '^[0-9a-f]{128}$' THEN
    RETURN;
  END IF;
  v_raw := decode(p_nonce, 'hex');
  IF substring(extensions.hmac(substring(v_raw FROM 1 FOR 48), private.fresh_start_key('mac'), 'sha256') FROM 1 FOR 16)
     IS DISTINCT FROM substring(v_raw FROM 49 FOR 16) THEN
    RETURN;
  END IF;
  v_plain := extensions.decrypt_iv(substring(v_raw FROM 17 FOR 32), private.fresh_start_key('enc'),
                                   substring(v_raw FROM 1 FOR 16), 'aes-cbc/pad:pkcs');
  IF length(v_plain) <> 24 THEN
    RETURN;
  END IF;
  user_id := encode(substring(v_plain FROM 1 FOR 16), 'hex')::uuid;
  issued_at := to_timestamp(('x' || encode(substring(v_plain FROM 17 FOR 8), 'hex'))::bit(64)::bigint);
END;
$$;

-- Spec §4.4: NULL lets the token through; otherwise the hook's error.
CREATE OR REPLACE FUNCTION private.access_token_refusal(p_event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid;
  v_kind text;
  v_created timestamptz;
  v_last timestamptz;
  v_seen timestamptz;
BEGIN
  IF p_event IS NULL OR jsonb_typeof(p_event) IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_event -> 'claims') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'hook:malformed_event';
  END IF;
  v_uid := (p_event ->> 'user_id')::uuid;
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'hook:malformed_event';
  END IF;

  -- (1) Any unresolved hold: no token, whatever the way in (a refresh
  -- included, so a parked account's old sessions stop within the hour).
  SELECT h.kind INTO v_kind
    FROM public.account_holds AS h
   WHERE h.user_id = v_uid AND h.resolved_at IS NULL
   ORDER BY CASE h.kind WHEN 'age_review' THEN 0 WHEN 'safety_review' THEN 1 ELSE 2 END
   LIMIT 1;
  IF v_kind IS NOT NULL THEN
    -- Final review I-1: a code sign-in to an age-held account unused for
    -- 180 days may be a recycled number's new owner, so it reads plain
    -- account_review (H1 without the device block, plan P-5). The hold
    -- stays; a refresh, or an age hold in use, keeps account_review:age.
    -- A held account gets no token, so its activity stopped at the hold.
    IF v_kind = 'age_review' AND p_event ->> 'authentication_method' = 'otp' THEN
      SELECT coalesce(a.last_active_at, u.created_at) INTO v_seen
        FROM public.users AS u
        LEFT JOIN public.account_activity AS a ON a.user_id = u.id
       WHERE u.id = v_uid;
      IF v_seen < now() - interval '180 days' THEN
        v_kind := 'age_review_dormant';
      END IF;
    END IF;
    RETURN jsonb_build_object('error', jsonb_build_object(
      'http_code', 403,
      'message', CASE WHEN v_kind = 'age_review' THEN 'account_review:age' ELSE 'account_review' END));
  END IF;

  -- A brand-new sign-up has no users row yet: nothing to check or record.
  SELECT u.created_at INTO v_created FROM public.users AS u WHERE u.id = v_uid;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  SELECT a.last_active_at INTO v_last FROM public.account_activity AS a WHERE a.user_id = v_uid;

  -- (2) A recycled number: a code sign-in to an account unused for 180
  -- days. A refresh (the same device) passes.
  IF p_event ->> 'authentication_method' = 'otp'
     AND private.spec1_flag_on('dormancy_rule')
     AND coalesce(v_last, v_created) < now() - interval '180 days' THEN
    RETURN jsonb_build_object('error', jsonb_build_object(
      'http_code', 403,
      'message', 'account_dormant:' || private.seal_fresh_start(v_uid, now())));
  END IF;

  -- (3) In use: the activity, at most every 12 hours.
  IF v_last IS NULL OR v_last < now() - interval '12 hours' THEN
    INSERT INTO public.account_activity AS a (user_id, last_active_at)
    VALUES (v_uid, now())
    ON CONFLICT (user_id) DO UPDATE
      SET last_active_at = EXCLUDED.last_active_at
      WHERE a.last_active_at < EXCLUDED.last_active_at - interval '12 hours';
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.attune_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_refusal jsonb;
  v_state text;
BEGIN
  BEGIN
    v_refusal := private.access_token_refusal(event);
  EXCEPTION WHEN query_canceled OR OTHERS THEN
    -- Fail open (R12): a bug or a slow database never locks everyone out.
    -- Counted and alerted (S-8); recording can never fail the hook.
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    BEGIN
      INSERT INTO private.auth_hook_failures (sqlstate) VALUES (v_state);
      PERFORM private.bump_metric_internal('auth_hook_fail_open');
    EXCEPTION WHEN query_canceled OR OTHERS THEN
      -- query_canceled is not in OTHERS: a timeout while recording
      -- still fails open (review M-1).
      NULL;
    END;
    RETURN event;
  END;
  RETURN coalesce(v_refusal, event);
END;
$$;

-- Revoked here as well as in the twin (the W1 precedent): the hosted
-- default privileges grant a new function to anon, authenticated and
-- service_role, and a late twin must not leave the hook, a nonce sealer or
-- the decision callable by a client.
REVOKE ALL ON public.account_activity, public.fresh_start_challenges FROM PUBLIC, anon, authenticated;
REVOKE ALL ON private.auth_hook_failures FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE private.auth_hook_failures_id_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fresh_start_key(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.seal_fresh_start(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.open_fresh_start(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.access_token_refusal(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.attune_access_token_hook(jsonb) FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
