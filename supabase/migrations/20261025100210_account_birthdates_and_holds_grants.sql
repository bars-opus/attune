-- Spec 1 W1b: grants for 20261025100200_account_birthdates_and_holds.sql.
-- No client grant on either table (a DOB is never readable from the phone);
-- service_role keeps DML (service_role_grants_test).
BEGIN;
REVOKE ALL ON public.account_birthdates, public.account_holds FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.account_birthdates, public.account_holds TO service_role;

REVOKE ALL ON FUNCTION private.age_on_utc_today(date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_age(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.place_account_hold(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_sign_up(text, date, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_my_birth_date(date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_age() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_sign_up(text, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_my_birth_date(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_age() TO authenticated;
COMMIT;
