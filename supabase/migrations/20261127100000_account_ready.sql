-- Entry gates (2026-11-27 audit, gap 2): one definition of "a complete
-- account", for the write policies and the invite functions to share.
--   * private.account_ready(p_uid uuid) -> boolean (STABLE, SECURITY
--     DEFINER, search_path ''): true only when
--       - a public.users row exists (complete_sign_up is the only writer
--         that creates one: record_eula_acceptance and the invite edge
--         functions no longer do, 20261127100040 / this wave),
--       - a date of birth is on file showing 18 or over, by the same rule
--         as everywhere else (private.age_on_utc_today, as account_age,
--         complete_sign_up and set_my_path use it),
--       - EULA version 2 or later is accepted, read as get_my_home_state,
--         set_my_path and dating_eligibility read it (eula_accepted_at set
--         and a 1-3 digit version >= 2; anything else is no consent),
--       - and no account hold is open (account_holds.resolved_at IS NULL,
--         any kind: age_review, safety_review and recovery_hold each close
--         the account, as accept_relationship_invite_v2 and
--         invite_inviter_unavailable already treat them).
--     NULL in, false out.
--   * public.my_account_ready() -> boolean: the caller's own answer
--     (auth.uid()), for RLS policies. authenticated has no USAGE on schema
--     private, so a policy cannot call private.account_ready itself; this
--     wrapper takes no argument, so it answers for no one but the caller.
-- Grants in 20261127100010_account_ready_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.account_ready(p_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_uid IS NOT NULL
     AND EXISTS (
       SELECT 1
         FROM public.users AS u
         JOIN public.account_birthdates AS b ON b.user_id = u.id
        WHERE u.id = p_uid
          AND u.eula_accepted_at IS NOT NULL
          AND coalesce(substring(u.eula_version FROM '^[0-9]{1,3}$')::integer, 0) >= 2
          AND private.age_on_utc_today(b.birth_date) >= 18)
     AND NOT EXISTS (
       SELECT 1 FROM public.account_holds AS h
        WHERE h.user_id = p_uid AND h.resolved_at IS NULL);
$$;

CREATE OR REPLACE FUNCTION public.my_account_ready()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.account_ready(auth.uid());
$$;

COMMENT ON FUNCTION private.account_ready(uuid) IS
  'Entry gates 2026-11-27: users row + DOB showing 18+ + EULA >= 2 + no open account hold.';
COMMENT ON FUNCTION public.my_account_ready() IS
  'Entry gates 2026-11-27: private.account_ready(auth.uid()), for write policies.';

COMMIT;
