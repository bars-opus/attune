-- Enforce append-only on the two audit tables (checklist 2.22).
--
-- wallet_transactions and withdrawal_audit_log must never be UPDATEd or
-- DELETEd after insert — that's the contract that makes them
-- reconcilable against provider records.
--
-- Today this is only enforced by convention. RLS prevents authenticated
-- clients from updating, but the SECURITY DEFINER service-side RPCs run
-- as the function owner and could in principle update the rows. A
-- malicious or buggy migration could too. The trigger below blocks both
-- paths.
--
-- Drop-and-recreate is required because we can't ALTER a trigger to
-- change its WHEN clause. The trigger is BEFORE so the row is rejected
-- before any state change.

-- ── wallet_transactions ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.forbid_audit_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
BEGIN
  RAISE EXCEPTION 'audit table %.% is append-only', TG_TABLE_SCHEMA, TG_TABLE_NAME
    USING ERRCODE = '42501';
END;
$function$;

COMMENT ON FUNCTION public.forbid_audit_mutation() IS
  'Trigger function that rejects UPDATE/DELETE on append-only audit tables. Used by wallet_transactions and withdrawal_audit_log.';

DROP TRIGGER IF EXISTS trg_wallet_transactions_immutable ON public.wallet_transactions;
CREATE TRIGGER trg_wallet_transactions_immutable
  BEFORE UPDATE OR DELETE ON public.wallet_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.forbid_audit_mutation();

DROP TRIGGER IF EXISTS trg_withdrawal_audit_log_immutable ON public.withdrawal_audit_log;
CREATE TRIGGER trg_withdrawal_audit_log_immutable
  BEFORE UPDATE OR DELETE ON public.withdrawal_audit_log
  FOR EACH ROW
  EXECUTE FUNCTION public.forbid_audit_mutation();

-- TRUNCATE is a separate statement type that triggers don't catch by
-- default. Block it explicitly with REVOKE on the owner.
REVOKE TRUNCATE ON public.wallet_transactions   FROM PUBLIC;
REVOKE TRUNCATE ON public.withdrawal_audit_log  FROM PUBLIC;

COMMENT ON TABLE public.wallet_transactions IS
  'Append-only ledger of wallet movements. Idempotent on (shop_id, reference). UPDATE/DELETE blocked by trigger.';

COMMENT ON TABLE public.withdrawal_audit_log IS
  'Append-only audit trail for withdrawal_requests state transitions. UPDATE/DELETE blocked by trigger.';
