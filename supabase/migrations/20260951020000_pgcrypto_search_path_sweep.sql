-- ---------------------------------------------------------------------
-- pgcrypto search_path: fix the remaining functions, as a sweep.
--
-- Same bug class already fixed three times for individual functions:
--   - 20260716140000_forums_opinions_anonymity_hardening.sql
--   - 20260903120000_chat_media_upload_intent_pgcrypto_search_path.sql
--   - 20260904120000_avatar_and_dating_intent_pgcrypto_search_path.sql
--
-- Root cause (unchanged): on a Supabase project pgcrypto lives in the
-- `extensions` schema, not `public`. Every migration's
-- `CREATE EXTENSION IF NOT EXISTS pgcrypto` is therefore a silent no-op
-- — the extension already exists, just elsewhere — so a function
-- declaring `SET search_path = public` cannot resolve a bare
-- `digest()`, `hmac()` or `gen_random_bytes()` call and fails at
-- runtime with "function digest(text, unknown) does not exist"
-- (SQLSTATE 42883).
--
-- This was caught by CI's SQL contract job, which had been failing on
-- main since at least 2026-09-16 with exactly those errors in
-- chat_import_contracts, games_contracts and (via dating_phone_hmac)
-- dating_exclusion_wiring_test. Verified locally by reproducing the
-- layout — pgcrypto installed into `extensions`, a plpgsql function
-- with `SET search_path = public` — which fails with the identical
-- message, and confirming that widening the search_path fixes it.
--
-- Fixed with ALTER FUNCTION rather than by re-declaring each body:
-- these are large functions spread across several migrations, and
-- ALTER changes ONLY the search_path setting. Re-pasting the bodies
-- would risk silently reverting later changes to them and would make
-- this migration's diff impossible to review for behaviour. Confirmed
-- locally that ALTER preserves SECURITY DEFINER and the body exactly,
-- setting only proconfig.
--
-- Every function below is listed with the migration holding its CURRENT
-- definition, so the signatures can be checked against the real source
-- rather than an older superseded copy.
-- ---------------------------------------------------------------------

-- 20260931120000_vault_backed_settings.sql — digest() on the outbox key.
ALTER FUNCTION public.enqueue_message_downstream_work()
  SET search_path = public, extensions;

-- 20260931120000_vault_backed_settings.sql — hmac() over the phone.
-- This one cascades: dating_exclusion_wiring_test's "expected 2
-- exclusion rows after ending, got 0" was a DOWNSTREAM symptom, since
-- the function returns NULL-ish/raises rather than producing a hash,
-- so no exclusion rows were written.
ALTER FUNCTION public.dating_phone_hmac(text)
  SET search_path = public, extensions;

-- 20260940010000_streak_photo_media_kind.sql — gen_random_bytes() for
-- the storage path. Same family as the chat-media fix in
-- 20260903120000, which a later redefinition re-broke by restating
-- `SET search_path = public`.
ALTER FUNCTION public.create_chat_media_upload_intent(uuid, text, text)
  SET search_path = public, extensions;

-- 20260930160000_truth_answer_safety.sql — digest() on the event key.
ALTER FUNCTION public.queue_truth_answer_safety()
  SET search_path = public, extensions;

-- 20260933170000_dating_candidate_generation.sql — digest() for the
-- deterministic shuffle seed.
ALTER FUNCTION public.run_dating_candidate_generation(text)
  SET search_path = public, extensions;

-- 20260705190000_chat_system_v1_3.sql — digest() on the import job's
-- source_event_key. These four are what chat_import_contracts.sql
-- exercises.
ALTER FUNCTION public.ingest_chat_import_batch(uuid, jsonb, boolean)
  SET search_path = public, extensions;
ALTER FUNCTION public.revoke_chat_import_request(uuid)
  SET search_path = public, extensions;
ALTER FUNCTION public.finalize_chat_import_after_safety()
  SET search_path = public, extensions;
ALTER FUNCTION public.delete_chat_import(uuid, boolean)
  SET search_path = public, extensions;
