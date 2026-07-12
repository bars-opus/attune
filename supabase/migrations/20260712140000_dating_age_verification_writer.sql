-- Dating age-verification writer (Fable review DATING-C2).
--
-- `dating_age_gate_holds` requires a row in `dating_age_verifications`, but that
-- table is REVOKE ALL FROM PUBLIC, anon, authenticated and NO writer existed —
-- so no user could ever satisfy the gate and `activate_dating_profile` always
-- raised `activation_gates_not_met`. The funnel was functionally dead, and the
-- danger was that whoever unblocked it under launch pressure would improvise a
-- CLIENT-writable integer (self-attested age), which the spec forbids
-- (checklist 3: "age is never a client-editable integer").
--
-- Fix: add a single legitimate writer that is SERVICE-ROLE ONLY. The birth date
-- and verification method come from an approved out-of-band KYC/DOB flow run by
-- the backend, never from the app JWT. authenticated/anon can neither insert
-- into the table (RLS + REVOKE, unchanged) nor execute this function.
--
-- This does NOT unblock the funnel on its own — it provides the one correct
-- path a verified-age backend job calls. Until such a job runs for a user, the
-- gate stays closed (current safe behavior).

CREATE OR REPLACE FUNCTION public.verify_dating_age(
  p_user_id uuid,
  p_birth_date date,
  p_verification_method text,
  p_verified_by uuid DEFAULT NULL,
  p_expires_at timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Defense in depth: even though EXECUTE is granted to service_role only, the
  -- function must never trust an app JWT. If invoked in a request context that
  -- carries an authenticated end-user role, refuse. A backend service_role call
  -- has no auth.uid()/jwt role, so this passes only for the intended caller.
  IF auth.role() IS NOT NULL AND auth.role() = 'authenticated' THEN
    RAISE EXCEPTION 'age_verification_is_backend_only' USING ERRCODE = '42501';
  END IF;

  -- The verified DOB comes from the KYC flow; the table CHECK already rejects a
  -- future birth_date. Enforce the adults-only floor here too so a bad upstream
  -- value can never seed a passing gate for a minor.
  IF p_birth_date > current_date - interval '18 years' THEN
    RAISE EXCEPTION 'age_below_minimum' USING ERRCODE = '22023';
  END IF;

  IF p_verification_method IS NULL OR char_length(p_verification_method) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'invalid_verification_method' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.dating_age_verifications(
    user_id, birth_date, verification_method, verified_at, expires_at, verified_by
  )
  VALUES (
    p_user_id, p_birth_date, p_verification_method, now(), p_expires_at, p_verified_by
  )
  ON CONFLICT (user_id) DO UPDATE
    SET birth_date          = EXCLUDED.birth_date,
        verification_method = EXCLUDED.verification_method,
        verified_at         = EXCLUDED.verified_at,
        expires_at          = EXCLUDED.expires_at,
        verified_by         = EXCLUDED.verified_by,
        revoked_at          = NULL,          -- re-verification clears a prior revoke
        updated_at          = now();
END;
$$;

-- Service-role only. Never grant to authenticated/anon (that would re-introduce
-- a client-controlled age path — the exact thing DATING-C2 forbids).
REVOKE ALL ON FUNCTION public.verify_dating_age(uuid, date, text, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verify_dating_age(uuid, date, text, uuid, timestamptz)
  TO service_role;

-- Companion revoker so a verification can be withdrawn (KYC reversal, fraud).
-- Also service-role only; closes the gate by stamping revoked_at.
CREATE OR REPLACE FUNCTION public.revoke_dating_age_verification(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() IS NOT NULL AND auth.role() = 'authenticated' THEN
    RAISE EXCEPTION 'age_verification_is_backend_only' USING ERRCODE = '42501';
  END IF;
  UPDATE public.dating_age_verifications
  SET revoked_at = COALESCE(revoked_at, now()),
      updated_at = now()
  WHERE user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_dating_age_verification(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_dating_age_verification(uuid)
  TO service_role;
