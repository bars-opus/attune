-- DEV / MANUAL TESTING ONLY. Never a migration (Spec 2 §8 W4a: until W7b's
-- console, a reviewer decides a human review here). Decides the identity
-- of one human-review session (pass, fail or ask_for_id; a person never
-- passes age), or sends an ID check waiting for review back for another ID
-- (ask_for_id only; fix round 1, I-2), on the development project only
-- (Spec 1's guard first; env:not_development stops it). A human review's
-- two photos are queued for deletion by the decision. An undecided ID
-- check expires after 72 hours waiting (the sweep). Usage, from the repo root:
--   psql -v session=<session uuid> -v outcome=pass -v reviewer=<reviewer uuid> \
--        -f supabase/sql/dev_dating_review_decide.sql
\set ON_ERROR_STOP 1
SELECT private.assert_development_project();
SELECT public.decide_dating_human_review(:'session'::uuid, :'outcome', :'reviewer'::uuid) AS decided;
