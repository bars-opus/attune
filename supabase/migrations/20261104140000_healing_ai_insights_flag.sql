-- Spec 1 W9e, migration 20 (spec 2.5, 4.7 #20, 8 W9e; owner approval O2):
-- healing_ai_insights, Healing's AI pause. One flag row, inserted false
-- (migrations never turn a flag on), read by generate-healing-portrait and
-- generate-healing-post-mortem (_shared/healing_ai_gate.ts): off means no
-- provider call for either stage and status 'paused', unless the crisis
-- check matches first: 'support_offered'. Its production gate row is the
-- same clinician gate as W9c. The gate row goes in first, so the flag is
-- gated from the moment it exists. No new object.
-- Grants in 20261104140010_healing_ai_insights_flag_grants.sql.
BEGIN;
-- public.feature_flags carries the production gate trigger: fail fast
-- rather than queue every flag read and write behind it.
SET LOCAL lock_timeout = '5s';

INSERT INTO private.flag_production_gates (flag_key, gate) VALUES
  ('healing_ai_insights', 'W9e gate (the W9c clinician gate): the clinician and the suicide-prevention reviewer sign the Healing support card and the self-harm corpus')
ON CONFLICT (flag_key) DO NOTHING;

INSERT INTO public.feature_flags (key, enabled) VALUES
  ('healing_ai_insights', false)
ON CONFLICT (key) DO NOTHING;
COMMIT;
