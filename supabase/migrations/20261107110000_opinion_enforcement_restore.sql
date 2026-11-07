-- Spec 1 W9d, migration 2 (spec §10 O4, owner approval O4; §4.3
-- complete_sign_up): a carried Opinions record comes back when an account
-- becomes the confirmed holder of the number (final review I-1 ruling).
--   * opinions_restore_on_auth_user: AFTER INSERT OR UPDATE OF phone,
--     phone_confirmed_at ON auth.users. Every account path (v1 and v2
--     sign-up, flow_signin_v2 on or off, a crafted client, a confirmed
--     number change) passes Auth's write that confirms the phone; no API
--     role can write auth.users. It restores on an account's first
--     confirmation, or a confirmed change of number; never on a
--     re-confirmation of the same number (a sign-in), never for Spec 1's
--     +999 placeholder (fresh start) or a parked account. It runs inside
--     Auth's own transaction, before any session for that account exists,
--     so no Opinions writer can post before it (they read
--     profiles.banned_until, which the restore writes, creating the
--     profile row when it doesn't exist yet). It never raises: a failure
--     warns and counts opinions.restore.failed; its lock waits are bounded
--     (lock_timeout 2s) and a cancel inside it (Auth's statement timeout)
--     is caught and counted the same, so it never blocks a sign-in or a
--     phone confirmation. It is the only restore path (final ruling):
--     complete_sign_up carries none, so no restore or count happens twice.
--   * private.opinion_restore_on_sign_up(user): a parked account restores
--     nothing (counted opinions.restore.parked_skipped); else the Opinions
--     records under the account's phone HMAC (dating_phone_hmac_for_user) are taken
--     (deleted) in one statement; those still inside their window
--     (purge_after > now(), private.opinion_carry_window() from the
--     deletion: owner decision W9d-1, the recycled-number rule) give the
--     profile their summed count and their latest live ban end (never
--     lowering either), and the account gets one stamp of what that added
--     under this number, so a later deletion carries it again instead of
--     the taken records being counted twice. Records past their window are
--     removed and restore nothing. No key: nothing restored, counted
--     opinions.restore.key_missing. A key whose fingerprint isn't ready
--     restores under the live key, counted opinions.restore.key_not_ready.
--     Restored: opinions.restore.applied. A stamp that fails is counted
--     opinions.restore.unstamped (batch-2 review M-3; the restore stands).
--     No notice is sent (the existing Opinions ban UI applies; nothing
--     else in Opinions changes).
--   * private.opinion_restores (coordinator ruling on batch-2 review I-1):
--     one row per restore (an account can restore again after a confirmed
--     change of number): the account, the source record ids, the count
--     and ban end it actually added (and the ban it replaced), the stamp it
--     wrote, when the source account was deleted and when it was restored.
--     No phone and no HMAC. Kept 90 days after the restore (the daily
--     opinion-enforcement-purge job, migration 1; coordinator ruling) or
--     until the account goes. No API role's.
--   * private.undo_opinion_restore(user) (owner-run; the service role's
--     only): takes back exactly what the account's restores added, never
--     the strikes the account earned itself: the count minus the restored
--     counts (floor 0); the ban back to the one the first restore replaced
--     when it came from the restore (final review M-1 ruling): it is still a
--     ban a restore set, or it is a strike's ban placed after the restore
--     while the account's own remaining strikes (fewer than 3) would never
--     have earned one. A ban the owner set directly stays, and so does one
--     the account's own 3 or more strikes earned. The stamps the same.
--     Idempotent: a
--     second call (or no restore) changes nothing, counted
--     opinions.restore.undo_noop; an undo is counted opinions.restore.undone.
--   * complete_sign_up re-created UNCHANGED from its LIVE body (Spec 1 W1b,
--     20261025100200; pg_get_functiondef on attune_spec3a): no W9d line. An
--     earlier draft of this file added a restore call; the final ruling
--     removed it (the auth.users trigger is the only restore path), and the
--     unchanged re-creation keeps a database that applied the draft
--     identical to production, where it is a no-op.
-- Grants in 20261107110010_opinion_enforcement_restore_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS private.opinion_restores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  source_record_ids uuid[] NOT NULL,
  restored_count integer NOT NULL CHECK (restored_count >= 0),
  restored_ban timestamptz,
  prior_ban timestamptz,
  stamp_id uuid,
  deleted_at timestamptz,
  restored_at timestamptz NOT NULL DEFAULT now(),
  undone_at timestamptz
);
-- A development database that applied this file's pre-release draft (one
-- row per account, keyed by user_id) takes the released shape; a fresh
-- database already has it.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'private' AND table_name = 'opinion_restores' AND column_name = 'id') THEN
    ALTER TABLE private.opinion_restores DROP CONSTRAINT opinion_restores_pkey;
    ALTER TABLE private.opinion_restores ADD COLUMN id uuid NOT NULL DEFAULT gen_random_uuid();
    ALTER TABLE private.opinion_restores ADD PRIMARY KEY (id);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS opinion_restores_user_id_idx ON private.opinion_restores (user_id);
ALTER TABLE private.opinion_restores ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.opinion_restores FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON TABLE private.opinion_restores IS
  'Spec 1 W9d (batch-2 review I-1): each Opinions restore at sign-up (what it added, from which carried records, when the source account was deleted), for support and private.undo_opinion_restore. No phone, no HMAC. Kept 90 days after the restore (private.opinion_enforcement_purge) or until the account goes.';

CREATE OR REPLACE FUNCTION private.opinion_restore_on_sign_up(p_user uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_hmac text;
  v_count integer;
  v_ban timestamptz;
  v_rows integer;
  v_ids uuid[];
  v_deleted_at timestamptz;
  v_old_count integer;
  v_old_ban timestamptz;
  v_added integer;
  v_set_ban timestamptz;
  v_stamp uuid;
BEGIN
  IF p_user IS NULL THEN
    RETURN 0;
  END IF;
  IF EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user AND u.phone_released_at IS NOT NULL) THEN
    -- Parked (Spec 1 O3, W9d-2): its number is presumed someone else's.
    PERFORM private.bump_metric_internal('opinions.restore.parked_skipped');
    RETURN 0;
  END IF;
  v_hmac := public.dating_phone_hmac_for_user(p_user);
  IF v_hmac IS NULL THEN
    IF public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NULL THEN
      PERFORM private.bump_metric_internal('opinions.restore.key_missing');
    END IF;
    RETURN 0;
  END IF;
  IF NOT private.dating_exclusion_key_ready() THEN
    PERFORM private.bump_metric_internal('opinions.restore.key_not_ready');
  END IF;
  WITH taken AS (
    DELETE FROM public.enforcement_records AS er
     WHERE er.scope = 'opinions' AND er.phone_hmac = v_hmac
    RETURNING er.id, er.confirmed_report_count, er.effect_until, er.purge_after, er.created_at
  )
  SELECT coalesce(sum(t.confirmed_report_count) FILTER (WHERE t.purge_after > now()), 0)::integer,
         max(t.effect_until) FILTER (WHERE t.purge_after > now() AND t.effect_until > now()),
         (count(*) FILTER (WHERE t.purge_after > now()))::integer,
         array_agg(t.id ORDER BY t.id) FILTER (WHERE t.purge_after > now()),
         min(t.created_at) FILTER (WHERE t.purge_after > now())
    INTO v_count, v_ban, v_rows, v_ids, v_deleted_at
    FROM taken AS t;
  IF v_count <= 0 AND v_ban IS NULL THEN
    RETURN 0;
  END IF;
  -- At an account's first confirmation no profile row exists yet: make it,
  -- so every Opinions writer reads the standing from the first request on.
  INSERT INTO public.profiles (id) VALUES (p_user) ON CONFLICT (id) DO NOTHING;
  SELECT p.confirmed_violation_count, p.banned_until INTO v_old_count, v_old_ban
    FROM public.profiles AS p WHERE p.id = p_user
    FOR UPDATE;
  UPDATE public.profiles AS p
     SET confirmed_violation_count = greatest(p.confirmed_violation_count, v_count),
         banned_until = CASE WHEN v_ban IS NULL THEN p.banned_until ELSE greatest(p.banned_until, v_ban) END
   WHERE p.id = p_user;
  -- What the restore actually added (a legacy account's own standing can
  -- already be higher: batch-2 review M-1).
  v_added := greatest(v_old_count, v_count) - v_old_count;
  v_set_ban := CASE WHEN v_ban IS NOT NULL AND (v_old_ban IS NULL OR v_old_ban < v_ban) THEN v_ban END;
  IF v_added > 0 OR v_set_ban IS NOT NULL THEN
    IF private.opinion_stamp_enforcement(p_user, v_added, v_set_ban) THEN
      SELECT s.id INTO v_stamp FROM private.opinion_enforcement_stamps AS s
       WHERE s.user_id = p_user AND s.phone_hmac = v_hmac;
    ELSE
      PERFORM private.bump_metric_internal('opinions.restore.unstamped');
    END IF;
  END IF;
  INSERT INTO private.opinion_restores (user_id, source_record_ids, restored_count, restored_ban, prior_ban,
                                        stamp_id, deleted_at)
  VALUES (p_user, coalesce(v_ids, '{}'), v_added, v_set_ban, v_old_ban, v_stamp, v_deleted_at);
  PERFORM private.bump_metric_internal('opinions.restore.applied');
  RETURN v_rows;
END;
$function$;

CREATE OR REPLACE FUNCTION private.undo_opinion_restore(p_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Owner-run (support script, owner checklist item 5): takes back exactly
-- what the account's restores added; never the strikes it earned itself.
DECLARE
  v_total integer;
  v_first timestamptz;
  v_prior timestamptz;
  v_bans timestamptz[];
  v_count integer;
  v_ban timestamptz;
  v_new_count integer;
  v_new_ban timestamptz;
BEGIN
  PERFORM 1 FROM private.opinion_restores AS o WHERE o.user_id = p_user_id AND o.undone_at IS NULL FOR UPDATE;
  SELECT coalesce(sum(o.restored_count), 0)::integer, min(o.restored_at),
         (array_agg(o.prior_ban ORDER BY o.restored_at, o.id))[1],
         array_agg(o.restored_ban) FILTER (WHERE o.restored_ban IS NOT NULL)
    INTO v_total, v_first, v_prior, v_bans
    FROM private.opinion_restores AS o WHERE o.user_id = p_user_id AND o.undone_at IS NULL;
  IF v_first IS NULL THEN
    PERFORM private.bump_metric_internal('opinions.restore.undo_noop');
    RETURN false;
  END IF;
  SELECT p.confirmed_violation_count, p.banned_until INTO v_count, v_ban
    FROM public.profiles AS p WHERE p.id = p_user_id
    FOR UPDATE;
  v_new_count := greatest(coalesce(v_count, 0) - v_total, 0);
  v_new_ban := CASE
    -- Still a ban a restore set.
    WHEN v_ban = ANY (v_bans) THEN v_prior
    -- A strike's ban placed after the restore, which the account's own
    -- remaining strikes (fewer than 3) would never have earned (M-1).
    WHEN v_ban > now() AND v_new_count < 3
         AND EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps AS s
                      WHERE s.user_id = p_user_id AND s.ban_until = v_ban AND s.stamped_at >= v_first)
      THEN v_prior
    -- A ban the owner set directly, or one the account's own strikes earned.
    ELSE v_ban END;
  UPDATE public.profiles AS p
     SET confirmed_violation_count = v_new_count, banned_until = v_new_ban
   WHERE p.id = p_user_id;
  UPDATE private.opinion_enforcement_stamps AS s
     SET strikes = greatest(s.strikes - t.n, 0)
    FROM (SELECT o.stamp_id, sum(o.restored_count)::integer AS n FROM private.opinion_restores AS o
           WHERE o.user_id = p_user_id AND o.undone_at IS NULL AND o.stamp_id IS NOT NULL
           GROUP BY o.stamp_id) AS t
   WHERE s.id = t.stamp_id;
  UPDATE private.opinion_enforcement_stamps AS s
     SET ban_until = v_prior
   WHERE s.user_id = p_user_id AND v_new_ban IS DISTINCT FROM v_ban AND s.ban_until = v_ban;
  UPDATE private.opinion_restores AS o SET undone_at = now() WHERE o.user_id = p_user_id AND o.undone_at IS NULL;
  PERFORM private.bump_metric_internal('opinions.restore.undone');
  RETURN true;
END;
$function$;

-- Final review I-1 (coordinator ruling): the restore point every account
-- path passes. Never raises.
CREATE OR REPLACE FUNCTION private.opinion_restore_on_auth_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
BEGIN
  -- Everything runs inside the caught block: nothing here can refuse
  -- Auth's write (a sign-in or a phone confirmation).
  BEGIN
    -- The account becomes the confirmed holder of NEW.phone: its first
    -- confirmation, or a confirmed change of number. A re-confirmation of
    -- the same number (a sign-in), no number, or Spec 1's +999 fresh-start
    -- placeholder restores nothing.
    IF NEW.phone_confirmed_at IS NULL OR nullif(btrim(coalesce(NEW.phone, '')), '') IS NULL
       OR NEW.phone ~ '^\+?999[0-9]{12}$' THEN
      RETURN NULL;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.phone_confirmed_at IS NOT NULL AND OLD.phone IS NOT DISTINCT FROM NEW.phone THEN
      RETURN NULL;
    END IF;
    PERFORM private.opinion_restore_on_sign_up(NEW.id);
  EXCEPTION WHEN OTHERS OR query_canceled THEN
    RAISE WARNING 'opinion_restore_on_auth_user:%', SQLSTATE;
    PERFORM private.bump_metric_internal('opinions.restore.failed');
  END;
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS opinions_restore_on_auth_user ON auth.users;
CREATE TRIGGER opinions_restore_on_auth_user
  AFTER INSERT OR UPDATE OF phone, phone_confirmed_at ON auth.users
  FOR EACH ROW EXECUTE FUNCTION private.opinion_restore_on_auth_user();

CREATE OR REPLACE FUNCTION public.complete_sign_up(p_display_name text, p_birth_date date, p_eula_version text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid constant uuid := auth.uid();
  v_today constant date := (now() AT TIME ZONE 'utc')::date;
  -- Controls dropped, whitespace collapsed, then trimmed (batch 3 fix round
  -- 1, M-1; final review M-1); a name with nothing visible is '' and is
  -- refused like an empty one.
  v_name constant text := private.normalize_display_name(p_display_name);
  v_phone text;
  v_stored date;
  v_age integer;
  v_created boolean;
  v_eula integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'signup:not_signed_in';
  END IF;
  v_phone := public.verified_phone(v_uid);
  IF v_phone IS NULL THEN
    RAISE EXCEPTION 'signup:phone_required';
  END IF;
  IF char_length(v_name) NOT BETWEEN 1 AND 40 OR v_name !~ '[^[:space:][:punct:][:digit:]]' THEN
    RAISE EXCEPTION 'signup:invalid_name';
  END IF;
  IF p_eula_version IS NULL OR p_eula_version !~ '^[0-9]{1,3}$' THEN
    RAISE EXCEPTION 'signup:eula_required';
  END IF;
  -- A5 is EULA v2: an older version is no consent (batch 3 fix round 1,
  -- M-3). Its own statement, so the cast never sees a non-numeric value.
  v_eula := p_eula_version::integer;
  IF v_eula < 2 THEN
    RAISE EXCEPTION 'signup:eula_required';
  END IF;

  SELECT b.birth_date INTO v_stored FROM public.account_birthdates AS b WHERE b.user_id = v_uid;
  IF v_stored IS NULL THEN
    IF p_birth_date IS NULL OR p_birth_date < DATE '1900-01-01' OR p_birth_date > v_today THEN
      RAISE EXCEPTION 'signup:invalid_birth_date';
    END IF;
    v_age := private.age_on_utc_today(p_birth_date);
  ELSE
    v_age := private.age_on_utc_today(v_stored);
  END IF;

  -- Under 18: refused before anything at all is written (D8).
  IF v_age < 18 THEN RAISE EXCEPTION 'signup:not_eligible'; END IF;

  INSERT INTO public.users AS u (id, phone, display_name, eula_accepted_at, eula_version)
  VALUES (v_uid, v_phone, v_name, now(), p_eula_version)
  ON CONFLICT (id) DO UPDATE
    SET phone = EXCLUDED.phone,
        display_name = CASE WHEN private.normalize_display_name(u.display_name) ~ '^\+?[0-9 ()-]*$'
                            THEN EXCLUDED.display_name ELSE u.display_name END,
        -- Consent never goes down (M-3): the stored version, compared as a
        -- number (a non-numeric one counts as none), keeps its time unless
        -- this one is newer.
        eula_accepted_at = CASE WHEN coalesce(substring(u.eula_version FROM '^[0-9]{1,3}$')::integer, -1) < v_eula
                                THEN EXCLUDED.eula_accepted_at ELSE u.eula_accepted_at END,
        eula_version = CASE WHEN coalesce(substring(u.eula_version FROM '^[0-9]{1,3}$')::integer, -1) < v_eula
                            THEN EXCLUDED.eula_version ELSE u.eula_version END;

  INSERT INTO public.profiles AS p (id, display_name)
  VALUES (v_uid, v_name)
  ON CONFLICT (id) DO UPDATE
    SET display_name = EXCLUDED.display_name
  WHERE private.normalize_display_name(p.display_name) ~ '^\+?[0-9 ()-]*$';

  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_uid, coalesce(v_stored, p_birth_date))
  ON CONFLICT (user_id) DO NOTHING;
  -- created = this call wrote the DOB (batch 3 fix round 1, M-2), not "no
  -- users row yet": a row record_eula_acceptance or ensureUserRow made first
  -- is still a first sign-up, and two racing first calls serialise on the
  -- PK, so exactly one is created and counted.
  v_created := FOUND;

  IF v_created THEN
    PERFORM private.bump_metric_internal('signup_completed');
  END IF;
  RETURN jsonb_build_object('age', v_age, 'created', v_created);
END;
$function$;

REVOKE ALL ON FUNCTION private.opinion_restore_on_sign_up(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.undo_opinion_restore(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.undo_opinion_restore(uuid) TO service_role;
REVOKE ALL ON FUNCTION private.opinion_restore_on_auth_user() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_sign_up(text, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_sign_up(text, date, text) TO authenticated;

COMMIT;
