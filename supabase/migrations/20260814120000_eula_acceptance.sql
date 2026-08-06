-- Records EULA/legal acceptance per user, so consent is captured once with a
-- durable timestamp rather than re-prompted on every sign-in.
--
-- Before this, LoginProfile showed the EULA sheet unconditionally ahead of the
-- phone-number entry, so a returning user re-accepted on every sign-in and
-- nothing was ever stored — there was no record of when (or whether) anyone
-- actually agreed. Repeated prompting is also a weaker legal position than one
-- timestamped acceptance.
--
-- `version` exists so amended terms can force a re-prompt: bump the version
-- constant in the app and anyone whose stored value is older sees the sheet
-- again. Without it the only way to re-obtain consent is to clear the column.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS eula_accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS eula_version text;

COMMENT ON COLUMN public.users.eula_accepted_at IS
  'When this user accepted the EULA. NULL means never accepted — the app must '
  'prompt before completing onboarding.';

COMMENT ON COLUMN public.users.eula_version IS
  'Which EULA version was accepted. Compared against the app''s current '
  'version constant so amended terms can re-prompt.';

-- Records acceptance for the calling user without requiring the client to hold
-- an UPDATE grant on public.users. SECURITY DEFINER + an explicit auth.uid()
-- match means a caller can only ever write their own row, never another user's.
--
-- The row may not exist yet: acceptance happens right after OTP verification,
-- while public.users is written later by onboarding submission. Insert a
-- minimal row (phone comes from the verified JWT, never client input) and let
-- onboarding fill in display_name/mode afterwards.
CREATE OR REPLACE FUNCTION public.record_eula_acceptance(p_version text)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_phone text;
  v_now timestamptz := now();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_version IS NULL OR btrim(p_version) = '' THEN
    RAISE EXCEPTION 'version_required';
  END IF;

  SELECT phone INTO v_phone FROM auth.users WHERE id = v_user_id;

  -- users.phone is NOT NULL and UNIQUE. Launch auth is phone-OTP only, so a
  -- verified caller always has one; bail rather than insert a placeholder,
  -- which would collide on the unique index for the second such user.
  IF v_phone IS NULL OR btrim(v_phone) = '' THEN
    RAISE EXCEPTION 'phone_required';
  END IF;

  INSERT INTO public.users (id, phone, display_name, eula_accepted_at, eula_version)
  VALUES (
    v_user_id,
    v_phone,
    '',
    v_now,
    p_version
  )
  ON CONFLICT (id) DO UPDATE
    SET eula_accepted_at = v_now,
        eula_version = p_version,
        updated_at = v_now;

  RETURN v_now;
END;
$$;

REVOKE ALL ON FUNCTION public.record_eula_acceptance(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_eula_acceptance(text) TO authenticated;

-- Returns the accepted version for the caller, or NULL if they have never
-- accepted. Kept as a function (rather than a direct select) so the client
-- needs no SELECT grant on columns beyond what it already reads.
CREATE OR REPLACE FUNCTION public.get_eula_acceptance()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT eula_version
  FROM public.users
  WHERE id = auth.uid()
    AND eula_accepted_at IS NOT NULL;
$$;

REVOKE ALL ON FUNCTION public.get_eula_acceptance() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_eula_acceptance() TO authenticated;
