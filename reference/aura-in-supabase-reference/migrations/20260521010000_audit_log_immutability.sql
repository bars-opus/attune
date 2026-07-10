-- ============================================================
-- payment_audit_log — enforce append-only immutability
-- ============================================================
--
-- The 20260516140000_payment_audit_log.sql migration created the table
-- with RLS for reads and locked down the INSERT path behind the
-- record_payment_audit SECURITY DEFINER RPC. What it did NOT do is
-- prevent the service_role from UPDATEing or DELETEing rows directly.
-- An audit log that can be rewritten is not an audit log.
--
-- Defense in two layers:
--   1. REVOKE UPDATE/DELETE/TRUNCATE from every role.
--   2. A BEFORE UPDATE OR DELETE OR TRUNCATE trigger that raises an
--      exception — catches a misconfigured grant from defeating the
--      revoke.
-- ============================================================

REVOKE UPDATE, DELETE, TRUNCATE ON TABLE payment_audit_log FROM PUBLIC;
REVOKE UPDATE, DELETE, TRUNCATE ON TABLE payment_audit_log FROM service_role;
REVOKE UPDATE, DELETE, TRUNCATE ON TABLE payment_audit_log FROM authenticated;
REVOKE UPDATE, DELETE, TRUNCATE ON TABLE payment_audit_log FROM anon;

CREATE OR REPLACE FUNCTION prevent_audit_log_modification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION 'payment_audit_log is append-only (% blocked)', TG_OP;
END;
$$;

DROP TRIGGER IF EXISTS payment_audit_log_no_update ON payment_audit_log;
CREATE TRIGGER payment_audit_log_no_update
  BEFORE UPDATE ON payment_audit_log
  FOR EACH STATEMENT
  EXECUTE FUNCTION prevent_audit_log_modification();

DROP TRIGGER IF EXISTS payment_audit_log_no_delete ON payment_audit_log;
CREATE TRIGGER payment_audit_log_no_delete
  BEFORE DELETE ON payment_audit_log
  FOR EACH STATEMENT
  EXECUTE FUNCTION prevent_audit_log_modification();

DROP TRIGGER IF EXISTS payment_audit_log_no_truncate ON payment_audit_log;
CREATE TRIGGER payment_audit_log_no_truncate
  BEFORE TRUNCATE ON payment_audit_log
  FOR EACH STATEMENT
  EXECUTE FUNCTION prevent_audit_log_modification();
