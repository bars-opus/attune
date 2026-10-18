-- Spec 5 (R5-9, R5-10; plan review C2, C3): the waiting step's clock and the
-- day-7 "use Attune on my own" action. Grants in 20261018130610.

-- Seconds since the caller's oldest never-accepted invite, expired ones
-- included, so minting a fresh code never resets the wait. NULL: none.
CREATE OR REPLACE FUNCTION public.get_my_invite_age()
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT extract(epoch FROM now() - min(r.created_at))::int
  FROM public.relationships r
  WHERE r.user_a = auth.uid() AND r.status = 'pending' AND r.user_b IS NULL;
$$;

-- Removes the caller's own never-accepted invites; with none left, the
-- app's mode sync resolves to personal mode. Returns how many went.
CREATE OR REPLACE FUNCTION public.withdraw_my_pending_invites()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_n int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'invite:not_signed_in'; END IF;
  DELETE FROM public.relationships r
  WHERE r.user_a = auth.uid() AND r.status = 'pending' AND r.user_b IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
