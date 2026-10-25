-- Spec 1 W1b, migration 3 of 6 (spec §4.7 #3): account_birthdates_and_holds.
--   * account_birthdates: the declared date of birth, write-once, never
--     shown (only an age is), never readable by a client;
--   * account_holds: whole-account holds (age_review, recovery_hold,
--     safety_review). Created here because set_my_birth_date and
--     get_my_home_state use them; the access-token hook that enforces them
--     lands in W6a;
--   * complete_sign_up writes users, profiles.display_name, the DOB and the
--     consent in one transaction, and an under-18 DOB writes nothing (D8).
-- Grants in 20261025100210_account_birthdates_and_holds_grants.sql.
BEGIN;
-- Both tables take a foreign key to public.users, which locks users (final
-- review M-3): fail fast rather than queue every users write behind a long
-- writer (sign-ins update users through the Auth mirror).
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.account_birthdates (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  birth_date date NOT NULL CONSTRAINT account_birthdates_birth_date_check CHECK (birth_date >= DATE '1900-01-01'),
  source text NOT NULL DEFAULT 'self_declared'
    CONSTRAINT account_birthdates_source_check CHECK (source IN ('self_declared', 'support_corrected')),
  declared_at timestamptz NOT NULL DEFAULT now(),
  corrected_at timestamptz,
  self_corrections smallint NOT NULL DEFAULT 0
    CONSTRAINT account_birthdates_self_corrections_check CHECK (self_corrections >= 0 AND self_corrections <= 1)
);
ALTER TABLE public.account_birthdates ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.account_holds (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  kind text NOT NULL CONSTRAINT account_holds_kind_check CHECK (kind IN ('age_review', 'recovery_hold', 'safety_review')),
  reason_ref text,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  resolved_at timestamptz,
  resolved_by text,
  PRIMARY KEY (user_id, kind)
);
ALTER TABLE public.account_holds ENABLE ROW LEVEL SECURITY;

-- Whole years on today's UTC date, the same rule the app's A2 screen uses.
-- It is not the person's local date: east of UTC a birthday arrives locally
-- up to 14 hours before the UTC date reaches it (stricter); west of UTC the
-- UTC date reaches it up to 12 hours before local midnight (more lenient).
CREATE OR REPLACE FUNCTION private.age_on_utc_today(p_birth_date date)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT extract(year FROM age((now() AT TIME ZONE 'utc')::date, p_birth_date))::integer;
$$;

CREATE OR REPLACE FUNCTION public.account_age(p_user uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.age_on_utc_today(b.birth_date)
    FROM public.account_birthdates AS b
   WHERE b.user_id = p_user;
$$;

CREATE OR REPLACE FUNCTION public.get_my_age()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.account_age(auth.uid());
$$;

-- Upsert an active hold. p_ref defaults to NULL so Spec 2's two-argument
-- call works (review I-7). A resolved hold of the same kind re-opens.
CREATE OR REPLACE FUNCTION public.place_account_hold(p_user uuid, p_kind text, p_ref text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_user IS NULL OR p_kind IS NULL THEN
    RAISE EXCEPTION 'hold:invalid';
  END IF;
  INSERT INTO public.account_holds AS h (user_id, kind, reason_ref, created_at, expires_at)
  VALUES (p_user, p_kind, p_ref, now(),
          CASE WHEN p_kind = 'recovery_hold' THEN now() + interval '180 days' END)
  ON CONFLICT (user_id, kind) DO UPDATE
    SET reason_ref = coalesce(EXCLUDED.reason_ref, h.reason_ref),
        created_at = CASE WHEN h.resolved_at IS NULL THEN h.created_at ELSE EXCLUDED.created_at END,
        expires_at = CASE WHEN h.resolved_at IS NULL THEN h.expires_at ELSE EXCLUDED.expires_at END,
        resolved_at = NULL,
        resolved_by = NULL;
END;
$$;

-- Names are read through private.normalize_display_name (migration 1, 1b:
-- the one definition of what a display name never keeps; final review M-1).

-- A5 (spec §3.3): the account, in one transaction. The phone comes from
-- auth.users, never from the caller. Idempotent for the offline replay
-- (PendingSignUp): a replay returns {age, created:false} and overwrites
-- nothing (a stored DOB wins; a non-empty name stays).
CREATE OR REPLACE FUNCTION public.complete_sign_up(p_display_name text, p_birth_date date, p_eula_version text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
$$;

-- A2 interstitial for legacy accounts (spec §3.15): once. Under 18 places an
-- age_review hold and returns not_eligible WITHOUT raising, so the hold and
-- the DOB commit.
CREATE OR REPLACE FUNCTION public.set_my_birth_date(p_birth_date date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_age integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'birth_date:not_signed_in';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = v_uid) THEN
    RAISE EXCEPTION 'birth_date:no_account';
  END IF;
  IF p_birth_date IS NULL OR p_birth_date < DATE '1900-01-01'
     OR p_birth_date > (now() AT TIME ZONE 'utc')::date THEN
    RAISE EXCEPTION 'birth_date:invalid';
  END IF;
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_uid, p_birth_date)
  ON CONFLICT (user_id) DO NOTHING;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'birth_date:already_set';
  END IF;
  v_age := private.age_on_utc_today(p_birth_date);
  IF v_age < 18 THEN
    PERFORM public.place_account_hold(v_uid, 'age_review', 'self_declared_birth_date');
    RETURN jsonb_build_object('status', 'not_eligible');
  END IF;
  RETURN jsonb_build_object('status', 'ok', 'age', v_age);
END;
$$;

-- Revoked here as well as in the twin (the verified_phone precedent; batch 2
-- review M3): the hosted default privileges grant EXECUTE on a new function
-- to anon and authenticated, and a failed or late twin push must not leave
-- any account's age readable, or a hold placeable, by uuid.
REVOKE ALL ON FUNCTION private.age_on_utc_today(date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_age(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.place_account_hold(uuid, text, text) FROM PUBLIC, anon, authenticated;

COMMIT;
