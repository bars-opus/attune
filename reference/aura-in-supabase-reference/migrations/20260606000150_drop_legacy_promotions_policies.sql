-- Phase 13 hotfix: drop the legacy `promotions` RLS policies left
-- behind by 20260606000000.
--
-- Symptom (2026-06-06): post-migration verification showed 8 policies
-- on `public.promotions` — the 4 new scoped policies from Wave 0 AND
-- the 4 legacy named policies from the original 20260604000100 backfill
-- ("Shop owners can ... their promotions"). The Wave 0 migration's
-- `DROP POLICY IF EXISTS promotions_owner_all` only removes a policy
-- with that literal name; the actual policies had different names.
--
-- Why this matters: the legacy policies have no `source = 'owner_defined'`
-- restriction, so RLS still permits an authenticated owner to INSERT a
-- row with `source = 'loyalty'` and `target_user_id = <arbitrary>` —
-- the exact fabrication surface Phase 13 was meant to close.
--
-- Idempotent: DROP POLICY IF EXISTS is safe to re-run.

DROP POLICY IF EXISTS "Shop owners can view their promotions"  ON public.promotions;
DROP POLICY IF EXISTS "Shop owners can insert their promotions" ON public.promotions;
DROP POLICY IF EXISTS "Shop owners can update their promotions" ON public.promotions;
DROP POLICY IF EXISTS "Shop owners can delete their promotions" ON public.promotions;
