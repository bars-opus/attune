-- supabase/migrations/20260903150000_dating_profile_photos_select_policy.sql
--
-- Fixes: chat image sends now succeed (storage.objects INSERT works), but
-- the message bubble renders "Unsupported message" instead of the image.
-- Root cause: reading the signed URL for the JUST-UPLOADED chat image
-- (bucket message-media) still triggers Postgres to evaluate EVERY SELECT
-- policy defined on storage.objects, including
-- dating_profile_photos_select_owner (a completely unrelated
-- dating-profile-photos policy) — the same
-- evaluate-every-policy-regardless-of-bucket behavior already fixed twice
-- tonight for INSERT policies (20260903130000, 20260903140000), now hitting
-- the identical class of bug on the SELECT side via createSignedUrl.
--
-- dating_profile_photos_select_owner's own EXISTS subquery
-- (`FROM dating_profile_photos p WHERE p.storage_key = objects.name AND
-- p.user_id = auth.uid()`) needs base SELECT privilege on
-- dating_profile_photos to even run — but that table was set up
-- (20260703203000_dating_mode_contract_hardening.sql) with RLS enabled,
-- `REVOKE ALL ... FROM anon, authenticated`, and only ever granted to
-- service_role (20260813130000_dating_photo_pipeline.sql) — authenticated
-- reads are meant to go through the list_dating_profile_photos() RPC only.
-- Confirmed live via debug print: StorageException(message: permission
-- denied for table dating_profile_photos, statusCode: 403) while signing a
-- chat-media URL, mirroring the exact 42501-inside-an-unrelated-policy
-- pattern already diagnosed for relationship_avatar_upload_intents /
-- message_media_upload_intents / dating_photo_upload_intents. Not a
-- regression from tonight's changes — this has always been broken,
-- surfaced only now that chat media reads are being exercised end-to-end.
--
-- Fix: same two-part fix as the other three tables tonight — a base SELECT
-- grant (satisfies the pre-RLS privilege check) plus an owner-scoped SELECT
-- policy (satisfies RLS itself, since RLS-enabled-with-zero-policies denies
-- all rows regardless of grants). Scoped to the row's own user_id, so this
-- opens no new visibility beyond what dating_profile_photos_select_owner's
-- subquery already assumes exists.
GRANT SELECT ON public.dating_profile_photos TO authenticated;

CREATE POLICY dating_profile_photos_select_own
ON public.dating_profile_photos FOR SELECT TO authenticated
USING (user_id = auth.uid());
