-- Spec 1 (app flow and identity) W1a, migration 1 of 6 (spec §4.7 #1):
-- identity_users_lockdown. Security hardening, never behind a flag (§2.5).
--   * users gains path, path_previous, path_chosen_at and phone_released_at;
--     their writers arrive in W1b (set_user_path_internal) and W6a.
--   * users.mode is retired (D3): the five dating functions below stop
--     writing it, as do the client upsert and both invite functions in the
--     same release. The column stays: SQL fixtures still insert it.
--   * users.phone is copied from auth.users (Q5, research 10 F-1): the client
--     loses the column grant (20261025100010) and a trigger mirrors Auth.
--     Invariant: the verified Auth phone, or NULL (NOT NULL goes). Every
--     insert takes it from Auth, a stale holder is moved off a claimed
--     number first, and a one-time pass reconciles legacy drift.
--   * profiles.banned_until and confirmed_violation_count are server-only,
--     and a profile with strikes or a live ban can't be deleted (D5, S-1).
-- Grants in 20261025100010_identity_users_lockdown_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- 1. users: the path columns ------------------------------------------------
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS path text
    CONSTRAINT users_path_check CHECK (path IN ('relationship', 'dating', 'just_me')),
  ADD COLUMN IF NOT EXISTS path_previous text
    CONSTRAINT users_path_previous_check CHECK (path_previous IN ('relationship', 'dating', 'just_me')),
  ADD COLUMN IF NOT EXISTS path_chosen_at timestamptz,
  ADD COLUMN IF NOT EXISTS phone_released_at timestamptz;

COMMENT ON COLUMN public.users.path IS
  'Spec 1: relationship | dating | just_me. Written only by set_user_path_internal (W1b).';
COMMENT ON COLUMN public.users.phone_released_at IS
  'Spec 1 W6a: set when the account is parked for a fresh start.';
COMMENT ON COLUMN public.users.mode IS
  'Retired (Spec 1 W1). Not written by the app, edge functions or SQL functions; not granted to clients. Kept so SQL fixtures still insert it.';

-- A NOT VALID check still binds every later UPDATE of an old row (a path
-- write, a phone sync), so a legacy name over 40 characters is trimmed
-- first; nothing else about the row changes.
UPDATE public.users SET display_name = left(display_name, 40)
 WHERE char_length(display_name) > 40;
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_display_name_length;
ALTER TABLE public.users
  ADD CONSTRAINT users_display_name_length CHECK (char_length(display_name) <= 40) NOT VALID;

-- 1b. users.display_name never keeps an invisible or bidi control (final
--     review M-1; controller ruling, as corrected). The one definition of the
--     characters a display name never keeps: U+200B, U+200E, U+200F
--     (zero-width space, LRM, RLM), U+202A-U+202E (bidi embeddings and
--     overrides), U+2060-U+2064 (invisible operators), U+2066-U+2069 (bidi
--     isolates) and U+FEFF. Left in, a partner sees a blank or a spoofed
--     name. ZWNJ (U+200C) and ZWJ (U+200D) stay exactly as typed: Persian and
--     Indic names and emoji sequences need them. A name with nothing visible
--     left once spaces, ZWNJ and ZWJ are set aside counts as no name.
--     complete_sign_up, get_my_home_state and the users trigger below all
--     read these helpers; the legacy client clamp mirrors them.
CREATE OR REPLACE FUNCTION private.strip_name_controls(p_name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT translate(p_name,
    U&'\200B\200E\200F\202A\202B\202C\202D\202E\2060\2061\2062\2063\2064\2066\2067\2068\2069\FEFF', '');
$$;

CREATE OR REPLACE FUNCTION private.name_is_blank(p_name text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT regexp_replace(translate(private.strip_name_controls(coalesce(p_name, '')), U&'\200C\200D', ''),
                        '\s', '', 'g') = '';
$$;

-- The name every W1 name rule reads: controls stripped, every whitespace run
-- (tabs and newlines too) collapsed to one space, the ends trimmed (batch 3
-- fix round 1, M-1), and '' when nothing visible is left.
CREATE OR REPLACE FUNCTION private.normalize_display_name(p_name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE WHEN private.name_is_blank(p_name) THEN ''
              ELSE btrim(regexp_replace(private.strip_name_controls(p_name), '\s+', ' ', 'g')) END;
$$;

-- Every write to users.display_name, a client's direct UPDATE included,
-- loses the controls, and one with nothing visible left is stored as ''
-- (no name). A name without any of those characters, ZWNJ or ZWJ is stored
-- exactly as written. Created after the trim above, so no stored name is
-- rewritten by this migration.
CREATE OR REPLACE FUNCTION private.users_display_name_clean()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_name text;
BEGIN
  IF NEW.display_name IS NULL THEN
    RETURN NEW;
  END IF;
  v_name := private.strip_name_controls(NEW.display_name);
  IF (v_name <> NEW.display_name OR v_name ~ U&'[\200C\200D]') AND private.name_is_blank(v_name) THEN
    v_name := '';
  END IF;
  NEW.display_name := v_name;
  RETURN NEW;
END;
$$;

-- Revoked here as well as in the twin (controller ruling after batch 3).
REVOKE ALL ON FUNCTION private.strip_name_controls(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.name_is_blank(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.normalize_display_name(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.users_display_name_clean() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS users_display_name_clean ON public.users;
CREATE TRIGGER users_display_name_clean
  BEFORE INSERT OR UPDATE OF display_name ON public.users
  FOR EACH ROW EXECUTE FUNCTION private.users_display_name_clean();

-- users.phone is the account's verified Auth phone, or NULL (fix round 2
-- ruling): NOT NULL goes so a stale or unverified copy can be cleared. UNIQUE
-- stays and admits any number of NULLs. Readers are NULL-safe
-- (dating_phone_hmac returns NULL; the app never reads users.phone).
ALTER TABLE public.users ALTER COLUMN phone DROP NOT NULL;
COMMENT ON COLUMN public.users.phone IS
  'The verified auth.users phone, or NULL. Written only from Auth: the insert guard users_phone_from_auth, the auth_users_phone_sync mirror and the one-time reconciliation (Spec 1 W1a). Not granted to clients.';

-- 2. users.phone mirrors auth.users ----------------------------------------
-- AFTER UPDATE only: fixtures that insert public.users directly keep
-- working. The mirrored value is the verified Auth phone, else NULL
-- (re-review 2, R2-1): it fires on phone and on phone_confirmed_at, so a
-- removed, blank or unconfirmed Auth phone clears users.phone and confirming
-- one writes it. A blank is NULL, never '' (users.phone is UNIQUE: a mirrored
-- '' would collide with the next blank).

-- Drift: before this migration users.phone was client-writable and Auth
-- changes weren't mirrored, so a users row can hold p_phone while its own
-- Auth phone is something else. Before p_owner (whose Auth phone p_phone is)
-- takes the number, such a stale row is moved to its own verified Auth phone
-- (freeing that number from a stale holder first, a bounded chain, so a
-- verified account is never parked while a squatter keeps its number), else
-- parked on +999 and 12 digits from a hash of its id, retried on collision
-- and never p_phone itself (the W6a parked form; the SMS hook refuses +999).
-- A row whose Auth phone really is p_phone is never touched: that unique
-- violation stands. Callers: the Auth mirror below and the users insert
-- guard (§2b).
CREATE OR REPLACE FUNCTION private.release_stale_users_phone(p_phone text, p_owner uuid, p_depth int DEFAULT 0)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_stale record;
  v_phone text;
  v_try int;
BEGIN
  IF nullif(btrim(p_phone), '') IS NULL THEN
    RETURN;
  END IF;
  FOR v_stale IN
    -- Its own Auth phone only when verified (R2-1): an unconfirmed one is
    -- no phone, so that row is parked instead.
    SELECT u.id,
           CASE WHEN a.phone_confirmed_at IS NOT NULL THEN nullif(btrim(a.phone), '') END AS auth_phone
      FROM public.users u
      LEFT JOIN auth.users a ON a.id = u.id
     WHERE u.phone = p_phone
       AND u.id <> p_owner
       AND a.phone IS DISTINCT FROM p_phone
       FOR UPDATE OF u
  LOOP
    v_phone := v_stale.auth_phone;
    IF v_phone IS NOT NULL AND v_phone <> p_phone AND p_depth < 3 THEN
      PERFORM private.release_stale_users_phone(v_phone, v_stale.id, p_depth + 1);
    END IF;
    v_try := 0;
    WHILE v_phone IS NULL OR v_phone = p_phone
          OR EXISTS (SELECT 1 FROM public.users x WHERE x.phone = v_phone AND x.id <> v_stale.id) LOOP
      EXIT WHEN v_try >= 20;  -- then users_phone_key refuses: fail closed
      v_try := v_try + 1;
      v_phone := '+999' || lpad(((('x' || left(md5(v_stale.id::text || ':' || v_try), 12))::bit(48)::bigint)
                                 % 1000000000000)::text, 12, '0');
    END LOOP;
    UPDATE public.users SET phone = v_phone WHERE id = v_stale.id;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION private.release_stale_users_phone(text, uuid, int) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.sync_users_phone_from_auth()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  -- The raw Auth value when it is confirmed and not blank (the same form the
  -- insert guard and the reconciliation store), else NULL.
  v_phone text := CASE WHEN NEW.phone_confirmed_at IS NOT NULL
                        AND nullif(btrim(NEW.phone), '') IS NOT NULL THEN NEW.phone END;
BEGIN
  IF v_phone IS NOT NULL THEN
    PERFORM private.release_stale_users_phone(v_phone, NEW.id);
  END IF;
  UPDATE public.users
     SET phone = v_phone
   WHERE id = NEW.id
     AND phone IS DISTINCT FROM v_phone;
  RETURN NULL;
END;
$$;

-- Fires only when the verified value changes (a phone change, a first
-- confirmation, a removal), not on every re-confirmation timestamp.
DROP TRIGGER IF EXISTS auth_users_phone_sync ON auth.users;
CREATE TRIGGER auth_users_phone_sync
  AFTER UPDATE OF phone, phone_confirmed_at ON auth.users
  FOR EACH ROW
  WHEN ((CASE WHEN NEW.phone_confirmed_at IS NOT NULL AND nullif(btrim(NEW.phone), '') IS NOT NULL
              THEN NEW.phone END)
        IS DISTINCT FROM
        (CASE WHEN OLD.phone_confirmed_at IS NOT NULL AND nullif(btrim(OLD.phone), '') IS NOT NULL
              THEN OLD.phone END))
  EXECUTE FUNCTION private.sync_users_phone_from_auth();

-- 2b. Every users insert takes its phone from Auth (fix round 2, R-1) -------
-- Invariant: users.phone is the account's verified Auth phone, or NULL.
-- Whatever the writer passes (record_eula_acceptance, complete_sign_up, the
-- invite functions' service-role upsert), a row whose Auth account has a
-- phone gets it when verified and NULL when not, and a stale holder of that
-- number is moved off it first, never the verified one. An Auth row with no
-- phone at all keeps the writer's value, a blank one stored as NULL: in
-- production every writer then passes NULL or "" (GoTrue's phone for a
-- phoneless account, which ensureUserRow passes on; a stored '' would make
-- the next phoneless account fail users_phone_key, re-review 2 R2-2) or
-- refuses (phone_required), and SQL fixtures that create auth.users(id) only
-- keep their phones. BEFORE INSERT also fires for INSERT ... ON CONFLICT,
-- before the conflict.
CREATE OR REPLACE FUNCTION private.users_phone_from_auth_on_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_auth record;
BEGIN
  SELECT a.phone, a.phone_confirmed_at IS NOT NULL AS verified INTO v_auth
    FROM auth.users a
   WHERE a.id = NEW.id
     AND nullif(btrim(a.phone), '') IS NOT NULL;
  IF NOT FOUND THEN
    NEW.phone := nullif(btrim(NEW.phone), '');
    RETURN NEW;
  END IF;
  IF NOT v_auth.verified THEN
    NEW.phone := NULL;
    RETURN NEW;
  END IF;
  PERFORM private.release_stale_users_phone(v_auth.phone, NEW.id);
  NEW.phone := v_auth.phone;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.users_phone_from_auth_on_insert() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS users_phone_from_auth ON public.users;
CREATE TRIGGER users_phone_from_auth
  BEFORE INSERT ON public.users
  FOR EACH ROW EXECUTE FUNCTION private.users_phone_from_auth_on_insert();

-- The client grants on users change here too, before the pass (batch 2
-- review M3): otherwise, between this COMMIT and the twin's (or for good, if
-- the twin push fails), a client keeps INSERT and UPDATE(phone) and a raw
-- PATCH could write drift back after the pass. The same three statements as
-- 20261025100010, which keeps them for the from-scratch replay.
REVOKE INSERT, UPDATE ON public.users FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.users FROM anon;
GRANT UPDATE (display_name, avatar_url, timezone) ON public.users TO authenticated;

-- 2c. One-time reconciliation of legacy drift (fix round 2, R-1) ------------
-- Phase 1 clears every users.phone that isn't the row's own verified Auth
-- phone (a stale or squatted copy, an unverified or missing Auth phone, a
-- blank). Phase 2 writes each verified Auth phone into its cleared row.
-- Auth's own UNIQUE keeps phase 2's numbers distinct; DISTINCT ON and the
-- NOT EXISTS only keep a database without that index (the local auth stub)
-- from failing here. Idempotent: a second run changes 0 rows. Returns the
-- number of rows changed.
CREATE OR REPLACE FUNCTION private.reconcile_users_phones()
RETURNS integer
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_cleared int;
  v_written int;
BEGIN
  UPDATE public.users u
     SET phone = NULL
   WHERE u.phone IS NOT NULL
     AND (nullif(btrim(u.phone), '') IS NULL
          OR NOT EXISTS (SELECT 1 FROM auth.users a
                          WHERE a.id = u.id
                            AND a.phone = u.phone
                            AND a.phone_confirmed_at IS NOT NULL));
  GET DIAGNOSTICS v_cleared = ROW_COUNT;

  UPDATE public.users u
     SET phone = s.phone
    FROM (SELECT DISTINCT ON (a.phone) a.id, a.phone
            FROM auth.users a
            JOIN public.users pu ON pu.id = a.id AND pu.phone IS NULL
           WHERE a.phone_confirmed_at IS NOT NULL
             AND nullif(btrim(a.phone), '') IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM public.users x WHERE x.phone = a.phone)
           ORDER BY a.phone, a.phone_confirmed_at, a.id) s
   WHERE u.id = s.id;
  GET DIAGNOSTICS v_written = ROW_COUNT;

  RETURN v_cleared + v_written;
END;
$$;
REVOKE ALL ON FUNCTION private.reconcile_users_phones() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN PERFORM private.reconcile_users_phones(); END $$;

-- 3. The verified phone, for definer callers (Spec 2 builds its HMAC on it).
CREATE OR REPLACE FUNCTION public.verified_phone(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT nullif(btrim(u.phone), '')
    FROM auth.users u
   WHERE u.id = p_user
     AND u.phone_confirmed_at IS NOT NULL;
$$;
-- Revoked here as well as in the twin: the hosted default privileges grant
-- EXECUTE on a new function to anon and authenticated, and a failed twin push
-- must not leave every confirmed phone readable by uuid.
REVOKE ALL ON FUNCTION public.verified_phone(uuid) FROM PUBLIC, anon, authenticated;

-- 4. profiles: the moderation columns are server-only (D5, S-1) ------------
-- Deliberately NOT SECURITY DEFINER: the whole check is "who is
-- current_user", which a definer function would rewrite to its owner
-- (precedent 20261019110300_system_notice_server_only.sql:19-31). Definer
-- functions and the service role pass; only a direct client write is
-- inspected, and only these two columns and deletes.
CREATE OR REPLACE FUNCTION private.guard_profile_moderation_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.banned_until := NULL;
    NEW.confirmed_violation_count := 0;
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF NEW.banned_until IS DISTINCT FROM OLD.banned_until OR NEW.confirmed_violation_count IS DISTINCT FROM OLD.confirmed_violation_count THEN
      RAISE EXCEPTION 'profile:moderation_column';
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.confirmed_violation_count > 0 OR OLD.banned_until > now() THEN
    RAISE EXCEPTION 'profile:moderation_locked';
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS profiles_guard_moderation_columns ON public.profiles;
CREATE TRIGGER profiles_guard_moderation_columns
  BEFORE INSERT OR UPDATE OR DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION private.guard_profile_moderation_columns();
-- No client deletes a profile (batch 1 review Important #1). Here as well as in
-- the twin, so there is no window, and a failed twin push leaves no strike
-- evasion (batch 3 fix round 1, M-6).
REVOKE DELETE ON public.profiles FROM authenticated, anon;

-- 5. The five dating functions, from their live bodies minus the users.mode
-- write (D3). Otherwise verbatim, except SET search_path = '' and the
-- schema-qualified return type: every name in the bodies is already
-- qualified, and every callee sets its own search_path.
CREATE OR REPLACE FUNCTION public.activate_dating_profile(p_idempotency_key text)
 RETURNS public.dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM public.check_dating_rate_limit('profile_activation',10,interval '1 day');
  IF NOT public.dating_flag_enabled('dating_mode_enabled')
     OR NOT public.dating_healing_gates_hold(v_user_id)
     OR NOT public.dating_age_gate_holds(v_user_id)
     OR NOT public.dating_account_in_good_standing(v_user_id)
     OR public.dating_has_relationship(v_user_id) THEN
    RAISE EXCEPTION 'activation_gates_not_met' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id=v_user_id FOR UPDATE;
  IF NOT FOUND OR v_enrollment.state NOT IN ('profile_draft','paused','active')
     OR v_enrollment.adults_only_confirmed_at IS NULL THEN
    RAISE EXCEPTION 'enrollment_incomplete' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.dating_profiles dp
    JOIN public.dating_preferences pref ON pref.user_id=dp.user_id
    WHERE dp.user_id=v_user_id AND dp.moderation_state='approved'
      AND jsonb_array_length(pref.gender_preferences)>0
      AND jsonb_array_length(pref.region_preferences)>0
      AND jsonb_array_length(pref.intention_preferences)>0
  ) THEN RAISE EXCEPTION 'profile_or_preferences_incomplete' USING ERRCODE='22023'; END IF;
  IF NOT public.claim_dating_idempotency('activate_dating_profile',p_idempotency_key) THEN RETURN v_enrollment; END IF;
  UPDATE public.dating_profiles SET profile_state='active',updated_at=now() WHERE user_id=v_user_id;
  UPDATE public.dating_enrollments SET state='active',activated_at=COALESCE(activated_at,now()),
    paused_at=NULL,exited_at=NULL,updated_at=now() WHERE user_id=v_user_id RETURNING * INTO v_enrollment;
  RETURN v_enrollment;
END;
$function$;

CREATE OR REPLACE FUNCTION public.pause_dating_mode(p_idempotency_key text)
 RETURNS public.dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.claim_dating_idempotency('pause_dating_mode', p_idempotency_key) THEN
    SELECT * INTO v_enrollment
    FROM public.dating_enrollments
    WHERE user_id = v_user_id;
    RETURN v_enrollment;
  END IF;

  UPDATE public.dating_profiles
  SET profile_state = 'paused',
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.dating_enrollments
  SET state = 'paused',
      paused_at = now(),
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING * INTO v_enrollment;

  RETURN v_enrollment;
END;
$function$;

CREATE OR REPLACE FUNCTION public.exit_dating_mode(p_idempotency_key text)
 RETURNS public.dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.claim_dating_idempotency('exit_dating_mode', p_idempotency_key) THEN
    SELECT * INTO v_enrollment
    FROM public.dating_enrollments
    WHERE user_id = v_user_id;
    RETURN v_enrollment;
  END IF;

  UPDATE public.dating_profiles
  SET profile_state = 'exited',
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.dating_enrollments
  SET state = 'exited',
      exited_at = now(),
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING * INTO v_enrollment;

  PERFORM public.invalidate_dating_for_user(v_user_id, 'exit');

  RETURN v_enrollment;
END;
$function$;

CREATE OR REPLACE FUNCTION public.pause_dating_for_relationship_user(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
BEGIN
  UPDATE public.dating_profiles
  SET profile_state = 'paused',
      updated_at = now()
  WHERE user_id = p_user_id
    AND profile_state = 'active';

  UPDATE public.dating_enrollments
  SET state = CASE
        WHEN state = 'suspended' THEN state
        ELSE 'paused'
      END,
      paused_at = COALESCE(paused_at, now()),
      updated_at = now()
  WHERE user_id = p_user_id
    AND state IN ('active', 'profile_draft', 'eligible_to_opt_in');

  PERFORM public.invalidate_dating_for_user(p_user_id, 'relationship_guard');
END;
$function$;
-- Server-only, here as well as in the twin (batch 3 fix round 1, M-6): the
-- hosted default privileges would otherwise let any signed-in user pause
-- anyone's Dating until the twin commits.
REVOKE ALL ON FUNCTION public.pause_dating_for_relationship_user(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_dating_profile(p_idempotency_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.claim_dating_idempotency('delete_dating_profile', p_idempotency_key) THEN
    RETURN;
  END IF;

  DELETE FROM public.dating_profile_photos
  WHERE user_id = v_user_id;

  DELETE FROM public.dating_preferences
  WHERE user_id = v_user_id;

  DELETE FROM public.dating_profiles
  WHERE user_id = v_user_id;

  UPDATE public.dating_enrollments
  SET state = CASE
        WHEN state = 'suspended' THEN state
        ELSE 'profile_draft'
      END,
      updated_at = now()
  WHERE user_id = v_user_id;

  PERFORM public.invalidate_dating_for_user(v_user_id, 'profile_deleted');
END;
$function$;

COMMIT;
