-- supabase/migrations/20260903140000_chat_media_upload_intent_select_policy.sql
--
-- Fixes: chat image sends still fail with `StorageException: new row
-- violates row-level security policy, statusCode: 403` even after
-- 20260903130000_chat_media_upload_intent_grants.sql granted SELECT to
-- authenticated. Confirmed live: the intent row genuinely exists with
-- correct storage_key/requester_id/used_at/expires_at (verified via SQL
-- editor), auth.uid() on the upload request matches requester_id exactly
-- (verified via temp debug print), yet a direct
-- `select * from message_media_upload_intents where storage_key = ...`
-- run through the app's own authenticated PostgREST session returns `[]`.
--
-- Root cause (correction of 20260903130000's own analysis, which assumed
-- "RLS enabled + zero policies + a GRANT" was a safe, working end state
-- for these intent tables — it is not): GRANT only satisfies Postgres's
-- base object-privilege check, which happens BEFORE row-level security is
-- consulted. It does not make any row visible. A table with
-- `ENABLE ROW LEVEL SECURITY` and zero policies denies every row to every
-- non-owner role, regardless of GRANTs — including to the EXISTS subquery
-- inside storage.objects's own insert policies
-- (message_media_insert_by_intent, relationship_avatars_insert_by_intent,
-- dating_profile_photos_insert_by_intent), which run as the calling
-- `authenticated` role, not as the table owner. So the subquery's EXISTS
-- was always evaluating over zero visible rows for every requester, for
-- every media type, since day one — the 20260705133000 migration that
-- introduced message_media_upload_intents never added a SELECT policy for
-- it, only the enforcement-side policies on storage.objects that assume
-- rows in this table are visible to the EXISTS check.
--
-- This bug has therefore always blocked every chat media upload in
-- production. It was masked in earlier manual testing (if any) only by
-- coincidence of test conditions, or never actually exercised end-to-end
-- before tonight. Not a regression from tonight's changes.
--
-- Fix: add an explicit SELECT policy to each *_upload_intents table,
-- scoped to "only the row's own requester" (mirrors the same ownership
-- check each table's corresponding storage.objects policy already
-- performs, so this grants no new visibility beyond what the EXISTS
-- subquery needs). Direct row access remains scoped — a user still cannot
-- see another user's upload intents.
CREATE POLICY message_media_upload_intents_select_own
ON public.message_media_upload_intents FOR SELECT TO authenticated
USING (requester_id = auth.uid());

CREATE POLICY relationship_avatar_upload_intents_select_own
ON public.relationship_avatar_upload_intents FOR SELECT TO authenticated
USING (requester_id = auth.uid());

CREATE POLICY dating_photo_upload_intents_select_own
ON public.dating_photo_upload_intents FOR SELECT TO authenticated
USING (user_id = auth.uid());
