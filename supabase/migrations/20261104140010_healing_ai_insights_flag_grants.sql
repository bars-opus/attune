-- Spec 1 W9e: grants for 20261104140000_healing_ai_insights_flag.sql. No new
-- object: the flag row and its gate row live in tables whose grants are
-- re-asserted here exactly as they stand (20260953200100,
-- 20261025100410): clients read flags and never write them; nobody but the
-- owner reaches the gate table.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.feature_flags FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.feature_flags TO authenticated;
REVOKE ALL ON private.flag_production_gates FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
