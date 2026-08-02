# Dating Mode Photo Upload, Moderation & Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full pipeline for Dating Mode profile photos — client-side prep, private upload, async Google Cloud Vision content/quality moderation, and an AWS Rekognition self-consistency identity check — so a photo only ever reaches a match after passing both, and no image-derived signal ever leaks into ranking.

**Architecture:** Client picks/prepares a photo with a new shared image-prep service (generalized from the existing chat-only `ChatImagePreparer`), requests a short-lived upload intent via RPC, uploads directly to a private Storage bucket, and inserts a `dating_profile_photos` row (validated server-side by trigger against the intent). Insertion enqueues a job in a new outbox table; a new `process-dating-photo` edge function (mirroring the existing `process-chat-media` claim-jobs worker) runs Vision checks and writes the moderation verdict. A separate `verify-dating-profile` edge function handles the one-shot verification-selfie flow against AWS Rekognition, writing only a pass/fail enum — never a score or embedding — to `dating_profiles`.

**Tech Stack:** Flutter/Riverpod/Supabase (existing), Deno edge functions (existing), Google Cloud Vision REST API (new), AWS Rekognition REST API via SigV4 (new).

## Global Constraints

- Never use photos, face embeddings, attractiveness, skin tone, or image-derived attributes in ranking. Verification is a hard eligibility filter only, never a rank signal. (Spec §4, §8)
- No similarity score or face embedding is ever persisted to any table, logged, or reaches `dating_feature_snapshots`. Only a bare enum + timestamp + method string. (Spec §4)
- A pending or failed/needs-review photo never enters candidate payloads; the gate is enforced at candidate-generation read time, not upload time. (Spec §2, §8)
- Client cannot set `moderation_state`, `verification_state`, or any trusted field directly — every transition is server-authoritative via `SECURITY DEFINER` RPC or trusted edge function. (Spec §2)
- EXIF and location metadata stripped before any image reaches storage or Vision. Random, opaque object keys — never expose bucket paths. (Spec §2)
- Face-detection or comparison failures route to human review (`needs_review`), never silent auto-reject. A Rekognition/Vision API failure (not a low-confidence result) also never silently auto-rejects — it retries, then lands in `needs_review` after exhausting attempts. (Spec §2, §4)
- Rejections get specific, actionable copy — never a bare "rejected." (Spec §2)
- Minimum 1 photo, maximum 4 photos. A profile with 0 photos may be saved as a draft but does not enter candidate generation. (Spec §5)
- No visible "Verified" badge or checkmark anywhere in the product. Verification is purely an internal eligibility gate. (Spec §6)
- Verification selfie must be captured via in-app camera only — no gallery import. (Spec §4)
- SafeSearch thresholds: reject `adult`/`violence` at `POSSIBLE` or above; reject `racy` at `LIKELY` or above; `medical`/`spoof` logged only, not rejecting, in v1. Face detection: `detectionConfidence` ≥ 0.7 required, else `needs_review`. Face not blurred/underexposed: `blurredLikelihood`/`underExposedLikelihood` ≤ `POSSIBLE`. Face-to-image area ratio ≥ 6%. Minimum image dimensions 600×600px. All thresholds live in server-side config, not hardcoded. (Spec §3)

---

## File Structure

**New files:**
- `supabase/migrations/20260813130000_dating_photo_pipeline.sql` — schema additions, outbox table, RPCs, RLS/grants.
- `supabase/functions/_shared/google_vision.ts` — Vision `annotate` REST caller (SafeSearch + Face Detection).
- `supabase/functions/_shared/aws_rekognition.ts` — Rekognition `CompareFaces` REST caller with SigV4 signing.
- `supabase/functions/upload-dating-photo/index.ts` — user-JWT function issuing upload intents.
- `supabase/functions/process-dating-photo/index.ts` — service-role worker, claims outbox jobs, runs Vision checks.
- `supabase/functions/verify-dating-profile/index.ts` — user-JWT function, one-shot selfie comparison.
- `lib/features/dating/domain/services/dating_image_preparer.dart` — shared client-side image prep (generalized from `ChatImagePreparer`).
- `lib/features/dating/data/models/dating_profile_photo.dart` — photo model.
- `lib/features/dating/presentation/screens/dating_photos_screen.dart` — upload/manage up to 4 photos.
- `lib/features/dating/presentation/screens/dating_verification_screen.dart` — disclosure + camera selfie capture.
- `test/features/dating/dating_image_preparer_test.dart`
- `test/features/dating/dating_profile_photo_model_test.dart`
- `supabase/functions/_shared/google_vision.test.ts`

**Modified files:**
- `lib/features/dating/data/repositories/dating_repository.dart` — add photo/verification methods.
- `lib/features/dating/presentation/providers/dating_providers.dart` — add photo/verification providers.
- `lib/features/chat/domain/services/chat_image_preparer.dart` — no functional change; Task 5 confirms it can delegate to the new shared preparer without behavior change (kept chat-only per its own docstring, but sharing the low-level MIME-sniff/decode helpers avoids duplicating that logic three ways).

---

### Task 1: Database migration — schema, outbox, RPCs

**Files:**
- Create: `supabase/migrations/20260813130000_dating_photo_pipeline.sql`

**Interfaces:**
- Produces: additive columns on `public.dating_profile_photos` (`rejection_reason text`, `reviewed_at timestamptz`, `attempts smallint`), updated `moderation_state` CHECK to include `'needs_review'`; additive columns on `public.dating_profiles` (`verification_state text`, `verification_method text`, `verified_at timestamptz`); new table `public.dating_photo_moderation_outbox`; new table `public.dating_photo_moderation_config` (thresholds); RPC `create_dating_photo_upload_intent(p_mime_type text) RETURNS TABLE(intent_id uuid, storage_key text, expires_at timestamptz, bucket text)`; RPC `insert_dating_profile_photo(p_intent_id uuid, p_position smallint) RETURNS uuid`; RPC `delete_dating_profile_photo(p_photo_id uuid) RETURNS void`; RPC `list_dating_profile_photos() RETURNS TABLE(id uuid, position smallint, moderation_state text, rejection_reason text, storage_key text, created_at timestamptz)`; RPC `resolve_dating_verification_review(p_user_id uuid, p_outcome text) RETURNS void` (service-role only); RPC `claim_dating_photo_jobs(p_limit int, p_photo_id uuid) RETURNS SETOF dating_photo_moderation_outbox`; RPC `recover_stale_dating_photo_jobs() RETURNS TABLE(recovered bigint)`; trigger `trigger_enqueue_dating_photo_processing` on `dating_photo_moderation_outbox` (AFTER INSERT) that auto-invokes `process-dating-photo` via `net.http_post`, mirroring `enqueue_chat_media_processing`.

- [ ] **Step 1: Write the migration file**

```sql
-- Dating Mode photo upload, moderation, and verification pipeline.
-- Extends the existing live dating_profile_photos / dating_profiles tables
-- (see 20260703203000_dating_mode_contract_hardening.sql) rather than
-- replacing them.

-- === 1. Extend dating_profile_photos ===

ALTER TABLE public.dating_profile_photos
  ADD COLUMN IF NOT EXISTS rejection_reason text,
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
  ADD COLUMN IF NOT EXISTS attempts smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS storage_bucket text NOT NULL DEFAULT 'dating-profile-photos';

ALTER TABLE public.dating_profile_photos
  DROP CONSTRAINT IF EXISTS dating_profile_photos_moderation_state_check;
ALTER TABLE public.dating_profile_photos
  ADD CONSTRAINT dating_profile_photos_moderation_state_check
  CHECK (moderation_state IN ('pending', 'approved', 'rejected', 'needs_review'));

ALTER TABLE public.dating_profile_photos
  DROP CONSTRAINT IF EXISTS dating_profile_photos_position_check;
ALTER TABLE public.dating_profile_photos
  ADD CONSTRAINT dating_profile_photos_position_check
  CHECK (position BETWEEN 1 AND 4);

-- === 2. Extend dating_profiles with verification state ===

ALTER TABLE public.dating_profiles
  ADD COLUMN IF NOT EXISTS verification_state text NOT NULL DEFAULT 'unverified'
    CHECK (verification_state IN ('unverified', 'pending', 'verified', 'needs_review')),
  ADD COLUMN IF NOT EXISTS verification_method text,
  ADD COLUMN IF NOT EXISTS verified_at timestamptz;

-- === 3. Upload intents (mirrors message_media_upload_intents) ===

CREATE TABLE IF NOT EXISTS public.dating_photo_upload_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  storage_key text NOT NULL UNIQUE,
  mime_type text NOT NULL,
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dating_photo_upload_intents_lookup
  ON public.dating_photo_upload_intents(user_id, expires_at DESC);

ALTER TABLE public.dating_photo_upload_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dating_photo_upload_intents FROM anon, authenticated;

-- === 4. Moderation outbox (mirrors message_media_processing_outbox) ===

CREATE TABLE IF NOT EXISTS public.dating_photo_moderation_outbox (
  photo_id uuid PRIMARY KEY REFERENCES public.dating_profile_photos(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  state text NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending', 'processing', 'done', 'dead_letter')),
  attempts smallint NOT NULL DEFAULT 0,
  last_error_code text,
  processing_started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dating_photo_moderation_outbox_pending
  ON public.dating_photo_moderation_outbox(state, created_at);

ALTER TABLE public.dating_photo_moderation_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dating_photo_moderation_outbox FROM anon, authenticated;

DROP TRIGGER IF EXISTS set_dating_photo_moderation_outbox_updated_at
  ON public.dating_photo_moderation_outbox;
CREATE TRIGGER set_dating_photo_moderation_outbox_updated_at
BEFORE UPDATE ON public.dating_photo_moderation_outbox
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- === 5. Moderation thresholds (server-side config, not hardcoded) ===

CREATE TABLE IF NOT EXISTS public.dating_photo_moderation_config (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  min_dimension_px int NOT NULL DEFAULT 600,
  min_face_confidence numeric NOT NULL DEFAULT 0.7,
  min_face_area_ratio numeric NOT NULL DEFAULT 0.06,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.dating_photo_moderation_config (id)
VALUES (true)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.dating_photo_moderation_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dating_photo_moderation_config FROM anon, authenticated;

-- === 6. Upload intent RPC (mirrors create_chat_media_upload_intent) ===

CREATE OR REPLACE FUNCTION public.create_dating_photo_upload_intent(
  p_mime_type text
)
RETURNS TABLE (
  intent_id uuid,
  storage_key text,
  expires_at timestamptz,
  bucket text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_extension text;
  v_storage_key text;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp') THEN
    RAISE EXCEPTION 'Unsupported image type';
  END IF;

  v_extension := CASE p_mime_type
    WHEN 'image/png' THEN 'png'
    WHEN 'image/webp' THEN 'webp'
    ELSE 'jpg'
  END;

  v_storage_key := 'dating-photos/' || encode(gen_random_bytes(16), 'hex') || '.' || v_extension;

  INSERT INTO public.dating_photo_upload_intents (
    user_id, storage_key, mime_type, expires_at
  ) VALUES (
    v_user_id, v_storage_key, p_mime_type, now() + interval '15 minutes'
  )
  RETURNING dating_photo_upload_intents.id, dating_photo_upload_intents.storage_key,
            dating_photo_upload_intents.expires_at
  INTO intent_id, storage_key, expires_at;

  bucket := 'dating-profile-photos';
  RETURN NEXT;
END;
$$;

-- === 7. Insert photo row (validates intent, enforces max 4, enqueues job) ===

CREATE OR REPLACE FUNCTION public.insert_dating_profile_photo(
  p_intent_id uuid,
  p_position smallint
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_user_id uuid;
  v_intent public.dating_photo_upload_intents%ROWTYPE;
  v_object storage.objects%ROWTYPE;
  v_photo_count int;
  v_photo_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_position NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'Invalid photo position';
  END IF;

  SELECT * INTO v_intent
  FROM public.dating_photo_upload_intents
  WHERE id = p_intent_id
    AND user_id = v_user_id
    AND used_at IS NULL
    AND expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Upload intent is invalid or expired';
  END IF;

  SELECT * INTO v_object FROM storage.objects o
  WHERE o.bucket_id = 'dating-profile-photos' AND o.name = v_intent.storage_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Uploaded object is missing';
  END IF;

  SELECT count(*) INTO v_photo_count
  FROM public.dating_profile_photos
  WHERE user_id = v_user_id;
  IF v_photo_count >= 4 THEN
    RAISE EXCEPTION 'Maximum of 4 photos already reached';
  END IF;

  UPDATE public.dating_photo_upload_intents SET used_at = now() WHERE id = p_intent_id;

  INSERT INTO public.dating_profile_photos (
    user_id, storage_key, position, moderation_state
  ) VALUES (
    v_user_id, v_intent.storage_key, p_position, 'pending'
  )
  ON CONFLICT (user_id, position) DO UPDATE
    SET storage_key = EXCLUDED.storage_key,
        moderation_state = 'pending',
        rejection_reason = NULL,
        reviewed_at = NULL,
        attempts = 0
  RETURNING id INTO v_photo_id;

  INSERT INTO public.dating_photo_moderation_outbox (photo_id, user_id)
  VALUES (v_photo_id, v_user_id)
  ON CONFLICT (photo_id) DO UPDATE
    SET state = 'pending', attempts = 0, last_error_code = NULL,
        processing_started_at = NULL, completed_at = NULL, updated_at = now();

  -- Replacing an existing approved photo invalidates prior verification,
  -- per spec §4 step 5: a new photo must also match the verification selfie.
  UPDATE public.dating_profiles
  SET verification_state = 'needs_review'
  WHERE user_id = v_user_id AND verification_state = 'verified';

  RETURN v_photo_id;
END;
$$;

-- === 8. Delete photo row ===

CREATE OR REPLACE FUNCTION public.delete_dating_profile_photo(
  p_photo_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  DELETE FROM public.dating_profile_photos
  WHERE id = p_photo_id AND user_id = v_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Photo not found';
  END IF;
END;
$$;

-- === 9. List own photos ===

CREATE OR REPLACE FUNCTION public.list_dating_profile_photos()
RETURNS TABLE (
  id uuid,
  position smallint,
  moderation_state text,
  rejection_reason text,
  storage_key text,
  created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.position, p.moderation_state, p.rejection_reason, p.storage_key, p.created_at
  FROM public.dating_profile_photos p
  WHERE p.user_id = auth.uid()
  ORDER BY p.position;
$$;

-- === 9b. Auto-invoke the worker on enqueue (mirrors
-- enqueue_chat_media_processing exactly — without this, jobs sit in
-- 'pending' forever with nothing to claim them) ===

CREATE OR REPLACE FUNCTION public.enqueue_dating_photo_processing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supabase_url text;
  v_service_role_key text;
BEGIN
  v_supabase_url := current_setting('app.settings.supabase_url', true);
  v_service_role_key := current_setting('app.settings.service_role_key', true);
  IF v_supabase_url IS NOT NULL AND v_service_role_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(
        url := v_supabase_url || '/functions/v1/process-dating-photo',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key,
          'apikey', v_service_role_key
        ),
        body := jsonb_build_object('photo_id', NEW.photo_id)
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_enqueue_dating_photo_processing
  ON public.dating_photo_moderation_outbox;
CREATE TRIGGER trigger_enqueue_dating_photo_processing
AFTER INSERT ON public.dating_photo_moderation_outbox
FOR EACH ROW EXECUTE FUNCTION public.enqueue_dating_photo_processing();

-- Fallback for when the HTTP call above fails (network blip, function cold
-- start) — mirrors this repo's recover_stale_chat_worker_leases pattern
-- being paired with a periodic sweep. recover_stale_dating_photo_jobs
-- (defined below in §12) only recovers jobs already claimed and stuck in
-- 'processing'; it does NOT pick up jobs that never got an HTTP call in the
-- first place. A separate periodic invocation of process-dating-photo
-- itself (which claims any 'pending' job, not just stale 'processing' ones)
-- is required as an operator-configured cron — same open item already
-- flagged in the manual verification checklist at the end of this plan.

-- === 10. Verification review resolution (service-role only; no admin UI yet,
-- but the resolution path must exist per spec §4) ===

CREATE OR REPLACE FUNCTION public.resolve_dating_verification_review(
  p_user_id uuid,
  p_outcome text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_outcome NOT IN ('verified', 'unverified') THEN
    RAISE EXCEPTION 'Invalid outcome';
  END IF;

  UPDATE public.dating_profiles
  SET verification_state = p_outcome,
      verified_at = CASE WHEN p_outcome = 'verified' THEN now() ELSE NULL END
  WHERE user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found';
  END IF;
END;
$$;

-- === 11. Claim jobs (mirrors claim_chat_media_jobs exactly) ===

CREATE OR REPLACE FUNCTION public.claim_dating_photo_jobs(
  p_limit int DEFAULT 20,
  p_photo_id uuid DEFAULT NULL
)
RETURNS SETOF public.dating_photo_moderation_outbox
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.dating_photo_moderation_outbox o
  SET state = 'processing',
      attempts = attempts + 1,
      processing_started_at = now(),
      updated_at = now(),
      last_error_code = NULL
  WHERE o.photo_id IN (
    SELECT photo_id FROM public.dating_photo_moderation_outbox
    WHERE state = 'pending'
      AND (p_photo_id IS NULL OR photo_id = p_photo_id)
    ORDER BY created_at
    FOR UPDATE SKIP LOCKED
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
  )
  RETURNING o.*;
$$;

-- === 12. Stale-lease recovery (mirrors recover_stale_chat_worker_leases) ===

CREATE OR REPLACE FUNCTION public.recover_stale_dating_photo_jobs()
RETURNS TABLE(recovered bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count bigint;
BEGIN
  UPDATE public.dating_photo_moderation_outbox
  SET state = CASE WHEN attempts >= 5 THEN 'dead_letter' ELSE 'pending' END,
      processing_started_at = NULL,
      last_error_code = 'stale_lease',
      completed_at = CASE WHEN attempts >= 5 THEN now() ELSE NULL END,
      updated_at = now()
  WHERE state = 'processing' AND processing_started_at < now() - interval '5 minutes';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  recovered := v_count;
  RETURN NEXT;
END;
$$;

-- === 13. Grants ===

REVOKE ALL ON FUNCTION public.create_dating_photo_upload_intent(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.insert_dating_profile_photo(uuid, smallint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_dating_profile_photo(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_dating_profile_photos() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_dating_verification_review(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_dating_photo_jobs(int, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.recover_stale_dating_photo_jobs() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_dating_photo_upload_intent(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.insert_dating_profile_photo(uuid, smallint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_dating_profile_photo(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_dating_profile_photos() TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_dating_verification_review(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_dating_photo_jobs(int, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.recover_stale_dating_photo_jobs() TO service_role;

-- service_role needs direct table access for the worker (same lesson as
-- 20260812120000_grant_service_role_core_tables.sql — RLS is bypassed for
-- service_role, but base table privileges are still checked first):
GRANT SELECT, UPDATE ON public.dating_profile_photos TO service_role;
GRANT SELECT ON public.dating_profile_moderation_config TO service_role;
GRANT SELECT, UPDATE ON public.dating_profiles TO service_role;
```

Note: the last GRANT line references `dating_profile_moderation_config` but the table created above is named `dating_photo_moderation_config` — fix this typo before running (use the exact name from Step 5).

- [ ] **Step 2: Fix the config-table grant typo and deploy the migration**

Before deploying, correct `dating_profile_moderation_config` to `dating_photo_moderation_config` in the final GRANT block (Step 13) to match the table created in Step 5.

Run: `cd /Users/user/attune && supabase db push`
Expected: migration applies with no errors.

- [ ] **Step 3: Manually verify the upload-intent → insert-photo flow via SQL**

Run as an authenticated test user (SQL editor with `set local role authenticated; set local "request.jwt.claims" = '{"sub":"<user-a-uuid>"}';`):
```sql
select * from public.create_dating_photo_upload_intent('image/jpeg');
-- note the returned storage_key, then simulate an uploaded object:
insert into storage.objects (bucket_id, name, owner)
values ('dating-profile-photos', '<storage_key_from_above>', '<user-a-uuid>');
select public.insert_dating_profile_photo('<intent_id_from_above>'::uuid, 1);
select * from public.list_dating_profile_photos();
```
Expected: the photo row appears with `moderation_state = 'pending'`, and a corresponding row exists in `dating_photo_moderation_outbox` with `state = 'pending'`.

- [ ] **Step 4: Verify the 4-photo cap**

Run the same flow 5 times (5 intents, 5 inserts at positions 1-4 then a 5th attempt).
Expected: the 5th `insert_dating_profile_photo` call raises `Maximum of 4 photos already reached`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260813130000_dating_photo_pipeline.sql
git commit -m "feat(dating): add photo upload/moderation/verification schema and RPCs"
```

---

### Task 2: Google Cloud Vision shared helper

**Files:**
- Create: `supabase/functions/_shared/google_vision.ts`
- Create: `supabase/functions/_shared/google_vision.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `analyzeDatingPhoto(params: { imageBytes: Uint8Array; apiKey: string }): Promise<VisionModerationResult>` where
  ```typescript
  interface VisionModerationResult {
    safeSearchFlags: { adult: string; violence: string; racy: string; medical: string; spoof: string };
    faceDetected: boolean;
    faceConfidence: number | null;
    faceBlurred: boolean;
    faceUnderexposed: boolean;
    faceAreaRatio: number | null; // 0-1, or null if no face
  }
  ```
  Also exports pure decision function `decideModerationOutcome(result: VisionModerationResult, config: { minFaceConfidence: number; minFaceAreaRatio: number }): { state: "approved" | "rejected" | "needs_review"; reason: string | null }`, kept separate from the network call so it is unit-testable without hitting Vision.

- [ ] **Step 1: Write the failing test for the decision function**

```typescript
// supabase/functions/_shared/google_vision.test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { decideModerationOutcome } from "./google_vision.ts";

const config = { minFaceConfidence: 0.7, minFaceAreaRatio: 0.06 };

Deno.test("decideModerationOutcome: approves a clean, confident, well-framed face", () => {
  const result = {
    safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "UNLIKELY", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: true,
    faceConfidence: 0.95,
    faceBlurred: false,
    faceUnderexposed: false,
    faceAreaRatio: 0.15,
  };
  const outcome = decideModerationOutcome(result, config);
  assertEquals(outcome.state, "approved");
  assertEquals(outcome.reason, null);
});

Deno.test("decideModerationOutcome: rejects adult content at POSSIBLE", () => {
  const result = {
    safeSearchFlags: { adult: "POSSIBLE", violence: "VERY_UNLIKELY", racy: "UNLIKELY", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: true,
    faceConfidence: 0.95,
    faceBlurred: false,
    faceUnderexposed: false,
    faceAreaRatio: 0.15,
  };
  const outcome = decideModerationOutcome(result, config);
  assertEquals(outcome.state, "rejected");
  assertEquals(outcome.reason, "adult_content_detected");
});

Deno.test("decideModerationOutcome: rejects racy only at LIKELY, not POSSIBLE", () => {
  const possible = {
    safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "POSSIBLE", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: true, faceConfidence: 0.95, faceBlurred: false, faceUnderexposed: false, faceAreaRatio: 0.15,
  };
  assertEquals(decideModerationOutcome(possible, config).state, "approved");

  const likely = { ...possible, safeSearchFlags: { ...possible.safeSearchFlags, racy: "LIKELY" } };
  assertEquals(decideModerationOutcome(likely, config).state, "rejected");
});

Deno.test("decideModerationOutcome: no face detected routes to needs_review, not rejected", () => {
  const result = {
    safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "VERY_UNLIKELY", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: false,
    faceConfidence: null,
    faceBlurred: false,
    faceUnderexposed: false,
    faceAreaRatio: null,
  };
  const outcome = decideModerationOutcome(result, config);
  assertEquals(outcome.state, "needs_review");
  assertEquals(outcome.reason, "no_face_detected");
});

Deno.test("decideModerationOutcome: low face confidence routes to needs_review", () => {
  const result = {
    safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "VERY_UNLIKELY", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: true,
    faceConfidence: 0.4,
    faceBlurred: false,
    faceUnderexposed: false,
    faceAreaRatio: 0.15,
  };
  const outcome = decideModerationOutcome(result, config);
  assertEquals(outcome.state, "needs_review");
  assertEquals(outcome.reason, "low_face_confidence");
});

Deno.test("decideModerationOutcome: blurred face rejects with specific reason", () => {
  const result = {
    safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "VERY_UNLIKELY", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: true,
    faceConfidence: 0.9,
    faceBlurred: true,
    faceUnderexposed: false,
    faceAreaRatio: 0.15,
  };
  const outcome = decideModerationOutcome(result, config);
  assertEquals(outcome.state, "rejected");
  assertEquals(outcome.reason, "face_blurred");
});

Deno.test("decideModerationOutcome: face too small in frame rejects with specific reason", () => {
  const result = {
    safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "VERY_UNLIKELY", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: true,
    faceConfidence: 0.9,
    faceBlurred: false,
    faceUnderexposed: false,
    faceAreaRatio: 0.02,
  };
  const outcome = decideModerationOutcome(result, config);
  assertEquals(outcome.state, "rejected");
  assertEquals(outcome.reason, "face_too_small");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/user/attune/supabase/functions/_shared && deno test google_vision.test.ts`
Expected: FAIL — `google_vision.ts` does not exist yet.

- [ ] **Step 3: Write the implementation**

```typescript
// supabase/functions/_shared/google_vision.ts

export interface VisionModerationResult {
  safeSearchFlags: {
    adult: string;
    violence: string;
    racy: string;
    medical: string;
    spoof: string;
  };
  faceDetected: boolean;
  faceConfidence: number | null;
  faceBlurred: boolean;
  faceUnderexposed: boolean;
  faceAreaRatio: number | null;
}

export interface ModerationConfig {
  minFaceConfidence: number;
  minFaceAreaRatio: number;
}

export interface ModerationOutcome {
  state: "approved" | "rejected" | "needs_review";
  reason: string | null;
}

const REJECT_AT_POSSIBLE = new Set(["POSSIBLE", "LIKELY", "VERY_LIKELY"]);
const REJECT_AT_LIKELY = new Set(["LIKELY", "VERY_LIKELY"]);

export function decideModerationOutcome(
  result: VisionModerationResult,
  config: ModerationConfig,
): ModerationOutcome {
  if (REJECT_AT_POSSIBLE.has(result.safeSearchFlags.adult)) {
    return { state: "rejected", reason: "adult_content_detected" };
  }
  if (REJECT_AT_POSSIBLE.has(result.safeSearchFlags.violence)) {
    return { state: "rejected", reason: "violent_content_detected" };
  }
  if (REJECT_AT_LIKELY.has(result.safeSearchFlags.racy)) {
    return { state: "rejected", reason: "racy_content_detected" };
  }

  if (!result.faceDetected) {
    return { state: "needs_review", reason: "no_face_detected" };
  }
  if (
    result.faceConfidence === null ||
    result.faceConfidence < config.minFaceConfidence
  ) {
    return { state: "needs_review", reason: "low_face_confidence" };
  }
  if (result.faceBlurred) {
    return { state: "rejected", reason: "face_blurred" };
  }
  if (result.faceUnderexposed) {
    return { state: "rejected", reason: "face_underexposed" };
  }
  if (
    result.faceAreaRatio === null ||
    result.faceAreaRatio < config.minFaceAreaRatio
  ) {
    return { state: "rejected", reason: "face_too_small" };
  }

  return { state: "approved", reason: null };
}

const VISION_URL = "https://vision.googleapis.com/v1/images:annotate";

export async function analyzeDatingPhoto(params: {
  imageBytes: Uint8Array;
  apiKey: string;
}): Promise<VisionModerationResult> {
  const base64 = encodeBase64(params.imageBytes);
  const response = await fetch(`${VISION_URL}?key=${params.apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      requests: [
        {
          image: { content: base64 },
          features: [
            { type: "SAFE_SEARCH_DETECTION" },
            { type: "FACE_DETECTION", maxResults: 5 },
          ],
        },
      ],
    }),
    signal: AbortSignal.timeout(10000),
  });

  if (!response.ok) {
    throw new Error(`vision_http_error_${response.status}`);
  }

  const payload = await response.json();
  const annotation = payload?.responses?.[0];
  if (!annotation) {
    throw new Error("vision_empty_response");
  }
  if (annotation.error) {
    throw new Error(`vision_api_error_${annotation.error.code ?? "unknown"}`);
  }

  const safeSearch = annotation.safeSearchAnnotation ?? {};
  const faces = annotation.faceAnnotations ?? [];
  const primaryFace = faces[0];

  let faceAreaRatio: number | null = null;
  if (primaryFace?.fdBoundingPoly?.vertices) {
    // Image dimensions are not returned by Vision; the caller supplies the
    // decoded image's own known dimensions via a second pass if area ratio
    // is required precisely. For v1, approximate using bounding-box pixel
    // span alone is insufficient without image dimensions, so this field is
    // computed by the caller (process-dating-photo) which already knows the
    // source image dimensions from the decode step, not here.
    faceAreaRatio = null;
  }

  return {
    safeSearchFlags: {
      adult: safeSearch.adult ?? "UNKNOWN",
      violence: safeSearch.violence ?? "UNKNOWN",
      racy: safeSearch.racy ?? "UNKNOWN",
      medical: safeSearch.medical ?? "UNKNOWN",
      spoof: safeSearch.spoof ?? "UNKNOWN",
    },
    faceDetected: faces.length > 0,
    faceConfidence: primaryFace?.detectionConfidence ?? null,
    faceBlurred: primaryFace?.blurredLikelihood
      ? REJECT_AT_POSSIBLE.has(primaryFace.blurredLikelihood)
      : false,
    faceUnderexposed: primaryFace?.underExposedLikelihood
      ? REJECT_AT_POSSIBLE.has(primaryFace.underExposedLikelihood)
      : false,
    faceAreaRatio,
  };
}

/** Exposed so process-dating-photo can compute the ratio once it has image
 * dimensions (from the decode step) and the raw fdBoundingPoly vertices. */
export function computeFaceAreaRatio(
  fdBoundingPolyVertices: Array<{ x?: number; y?: number }>,
  imageWidth: number,
  imageHeight: number,
): number | null {
  if (fdBoundingPolyVertices.length < 4 || imageWidth <= 0 || imageHeight <= 0) {
    return null;
  }
  const xs = fdBoundingPolyVertices.map((v) => v.x ?? 0);
  const ys = fdBoundingPolyVertices.map((v) => v.y ?? 0);
  const faceWidth = Math.max(...xs) - Math.min(...xs);
  const faceHeight = Math.max(...ys) - Math.min(...ys);
  const faceArea = faceWidth * faceHeight;
  const imageArea = imageWidth * imageHeight;
  return imageArea > 0 ? faceArea / imageArea : null;
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/user/attune/supabase/functions/_shared && deno test google_vision.test.ts`
Expected: PASS, 7/7 tests.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/google_vision.ts supabase/functions/_shared/google_vision.test.ts
git commit -m "feat(dating): add Google Cloud Vision moderation helper"
```

---

### Task 3: AWS Rekognition shared helper

**Files:**
- Create: `supabase/functions/_shared/aws_rekognition.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks (independent of Task 2).
- Produces: `compareFaces(params: { sourceImageBytes: Uint8Array; targetImageBytes: Uint8Array; accessKeyId: string; secretAccessKey: string; region: string }): Promise<{ matched: boolean; similarity: number | null }>`. The `similarity` field exists only for the caller's in-memory pass/fail decision within the same function invocation — per spec §4, the caller (Task 6) must never persist this value.

- [ ] **Step 1: Write the implementation**

Rekognition's `CompareFaces` API requires AWS Signature Version 4 request signing. This is implemented directly (no AWS SDK dependency, consistent with this codebase's existing pattern of calling REST APIs directly from Deno edge functions rather than pulling in heavy SDKs).

```typescript
// supabase/functions/_shared/aws_rekognition.ts

export interface CompareFacesResult {
  matched: boolean;
  similarity: number | null;
}

const SIMILARITY_THRESHOLD = 90; // percent; tune after real-world testing

export async function compareFaces(params: {
  sourceImageBytes: Uint8Array;
  targetImageBytes: Uint8Array;
  accessKeyId: string;
  secretAccessKey: string;
  region: string;
}): Promise<CompareFacesResult> {
  const body = JSON.stringify({
    SourceImage: { Bytes: encodeBase64(params.sourceImageBytes) },
    TargetImage: { Bytes: encodeBase64(params.targetImageBytes) },
    SimilarityThreshold: 0,
  });

  const host = `rekognition.${params.region}.amazonaws.com`;
  const headers = await signRequest({
    method: "POST",
    host,
    region: params.region,
    service: "rekognition",
    target: "RekognitionService.CompareFaces",
    body,
    accessKeyId: params.accessKeyId,
    secretAccessKey: params.secretAccessKey,
  });

  const response = await fetch(`https://${host}/`, {
    method: "POST",
    headers,
    body,
    signal: AbortSignal.timeout(10000),
  });

  if (!response.ok) {
    throw new Error(`rekognition_http_error_${response.status}`);
  }

  const payload = await response.json();
  const matches = payload?.FaceMatches ?? [];
  if (matches.length === 0) {
    return { matched: false, similarity: null };
  }
  const bestSimilarity = Math.max(
    ...matches.map((m: { Similarity?: number }) => m.Similarity ?? 0),
  );
  return {
    matched: bestSimilarity >= SIMILARITY_THRESHOLD,
    similarity: bestSimilarity,
  };
}

async function signRequest(params: {
  method: string;
  host: string;
  region: string;
  service: string;
  target: string;
  body: string;
  accessKeyId: string;
  secretAccessKey: string;
}): Promise<Record<string, string>> {
  const encoder = new TextEncoder();
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "");
  const dateStamp = amzDate.slice(0, 8);

  const canonicalHeaders =
    `content-type:application/x-amz-json-1.1\n` +
    `host:${params.host}\n` +
    `x-amz-date:${amzDate}\n` +
    `x-amz-target:${params.target}\n`;
  const signedHeaders = "content-type;host;x-amz-date;x-amz-target";
  const payloadHash = await sha256Hex(params.body);

  const canonicalRequest = [
    params.method,
    "/",
    "",
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join("\n");

  const credentialScope = `${dateStamp}/${params.region}/${params.service}/aws4_request`;
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    credentialScope,
    await sha256Hex(canonicalRequest),
  ].join("\n");

  const signingKey = await getSignatureKey(
    params.secretAccessKey,
    dateStamp,
    params.region,
    params.service,
  );
  const signature = toHex(await hmac(signingKey, stringToSign));

  const authorizationHeader =
    `AWS4-HMAC-SHA256 Credential=${params.accessKeyId}/${credentialScope}, ` +
    `SignedHeaders=${signedHeaders}, Signature=${signature}`;

  return {
    "Content-Type": "application/x-amz-json-1.1",
    "X-Amz-Date": amzDate,
    "X-Amz-Target": params.target,
    Authorization: authorizationHeader,
  };

  async function hmac(key: Uint8Array, msg: string): Promise<Uint8Array> {
    const cryptoKey = await crypto.subtle.importKey(
      "raw",
      key,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const sig = await crypto.subtle.sign("HMAC", cryptoKey, encoder.encode(msg));
    return new Uint8Array(sig);
  }

  async function getSignatureKey(
    secret: string,
    date: string,
    region: string,
    service: string,
  ): Promise<Uint8Array> {
    const kDate = await hmac(encoder.encode(`AWS4${secret}`), date);
    const kRegion = await hmac(kDate, region);
    const kService = await hmac(kRegion, service);
    return await hmac(kService, "aws4_request");
  }
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return toHex(new Uint8Array(digest));
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}
```

- [ ] **Step 2: Type-check with Deno**

Run: `cd /Users/user/attune/supabase/functions/_shared && deno check aws_rekognition.ts`
Expected: no type errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/_shared/aws_rekognition.ts
git commit -m "feat(dating): add AWS Rekognition CompareFaces helper with SigV4 signing"
```

Note: this task has no automated test against the live Rekognition API (would require real AWS credentials and cost money per call). `deno check` type-checking plus Task 6's manual smoke test is the verification for this task, consistent with how this codebase already handles other external-API edge functions with no local mock.

---

### Task 4: `process-dating-photo` edge function

**Files:**
- Create: `supabase/functions/process-dating-photo/index.ts`

**Interfaces:**
- Consumes: `analyzeDatingPhoto`, `computeFaceAreaRatio`, `decideModerationOutcome` from `_shared/google_vision.ts` (Task 2); RPC `claim_dating_photo_jobs` from Task 1's migration; table `dating_photo_moderation_config` for thresholds.
- Produces: an HTTP endpoint (service-role only) that claims and processes pending `dating_photo_moderation_outbox` jobs, writing `moderation_state`/`rejection_reason`/`reviewed_at`/`attempts` on `dating_profile_photos` and finishing the outbox row.

- [ ] **Step 1: Write the implementation**

```typescript
// supabase/functions/process-dating-photo/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  jsonResponse,
  requireServiceRole,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import {
  analyzeDatingPhoto,
  computeFaceAreaRatio,
  decideModerationOutcome,
} from "../_shared/google_vision.ts";

const MAX_ATTEMPTS = 5;
const VISION_API_KEY = Deno.env.get("GOOGLE_VISION_API_KEY");

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    if (!VISION_API_KEY) {
      throw new Error("missing_vision_api_key");
    }
    const supabase = serviceRoleClient();
    const body = await req.json().catch(() => ({}));
    const requestedId = typeof body.photo_id === "string" ? body.photo_id : null;

    const { data: jobs, error } = await supabase.rpc("claim_dating_photo_jobs", {
      p_limit: requestedId ? 1 : 20,
      p_photo_id: requestedId,
    });
    if (error) throw error;

    const { data: configRows } = await supabase
      .from("dating_photo_moderation_config")
      .select("min_face_confidence, min_face_area_ratio")
      .limit(1);
    const config = configRows?.[0] ?? {
      min_face_confidence: 0.7,
      min_face_area_ratio: 0.06,
    };

    let processed = 0;
    for (const job of jobs ?? []) {
      try {
        const { data: photo, error: photoError } = await supabase
          .from("dating_profile_photos")
          .select("id, storage_key")
          .eq("id", job.photo_id)
          .single();
        if (photoError || !photo) throw new Error("photo_missing");

        const { data: image, error: downloadError } = await supabase.storage
          .from("dating-profile-photos")
          .download(photo.storage_key);
        if (downloadError || !image) throw new Error("decode_failed");

        const bytes = new Uint8Array(await image.arrayBuffer());
        const dimensions = await readImageDimensions(bytes);
        if (!dimensions || dimensions.width < 600 || dimensions.height < 600) {
          await writeVerdict(supabase, photo.id, "rejected", "image_too_small");
          await finish(supabase, job.photo_id, "done", null);
          processed++;
          continue;
        }

        const visionResult = await analyzeDatingPhoto({
          imageBytes: bytes,
          apiKey: VISION_API_KEY,
        });

        // Compute the precise face-area ratio using the raw bounding box and
        // our own known image dimensions (Vision doesn't return image size).
        const rawResponse = await fetch(
          `https://vision.googleapis.com/v1/images:annotate?key=${VISION_API_KEY}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              requests: [{
                image: { content: base64(bytes) },
                features: [{ type: "FACE_DETECTION", maxResults: 1 }],
              }],
            }),
            signal: AbortSignal.timeout(10000),
          },
        );
        const rawPayload = await rawResponse.json();
        const vertices =
          rawPayload?.responses?.[0]?.faceAnnotations?.[0]?.fdBoundingPoly?.vertices;
        const faceAreaRatio = vertices
          ? computeFaceAreaRatio(vertices, dimensions.width, dimensions.height)
          : null;

        const outcome = decideModerationOutcome(
          { ...visionResult, faceAreaRatio },
          {
            minFaceConfidence: config.min_face_confidence,
            minFaceAreaRatio: config.min_face_area_ratio,
          },
        );

        await writeVerdict(supabase, photo.id, outcome.state, outcome.reason);
        await finish(supabase, job.photo_id, "done", null);
        processed++;
      } catch (jobError) {
        const dead = Number(job.attempts ?? 0) >= MAX_ATTEMPTS;
        if (dead) {
          await writeVerdict(supabase, job.photo_id, "needs_review", "moderation_failed");
        }
        await finish(
          supabase,
          job.photo_id,
          dead ? "dead_letter" : "pending",
          errorCode(jobError),
        );
      }
    }
    return jsonResponse({ success: true, processed });
  } catch (error) {
    return jsonResponse({ success: false, error: errorCode(error) }, 500);
  }
});

async function writeVerdict(
  supabase: ReturnType<typeof serviceRoleClient>,
  photoId: string,
  state: "approved" | "rejected" | "needs_review",
  reason: string | null,
) {
  const { error } = await supabase
    .from("dating_profile_photos")
    .update({
      moderation_state: state,
      rejection_reason: reason,
      reviewed_at: new Date().toISOString(),
    })
    .eq("id", photoId);
  if (error) throw error;
}

async function finish(
  supabase: ReturnType<typeof serviceRoleClient>,
  photoId: string,
  state: "pending" | "done" | "dead_letter",
  code: string | null,
) {
  const { error } = await supabase.from("dating_photo_moderation_outbox")
    .update({
      state,
      last_error_code: code,
      processing_started_at: state === "pending" ? null : undefined,
      completed_at: state === "done" || state === "dead_letter"
        ? new Date().toISOString()
        : null,
      updated_at: new Date().toISOString(),
    })
    .eq("photo_id", photoId).eq("state", "processing");
  if (error) throw error;
}

async function readImageDimensions(
  bytes: Uint8Array,
): Promise<{ width: number; height: number } | null> {
  // Minimal JPEG/PNG header parse sufficient for the dimension gate; a full
  // decode is not required here since Vision already validated decodability.
  if (bytes.length > 24 && bytes[0] === 0x89 && bytes[1] === 0x50) {
    // PNG: width/height are big-endian uint32 at offset 16/20.
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    return { width: view.getUint32(16), height: view.getUint32(20) };
  }
  if (bytes.length > 4 && bytes[0] === 0xFF && bytes[1] === 0xD8) {
    // JPEG: scan markers for SOF0/SOF2 to find dimensions.
    let offset = 2;
    while (offset < bytes.length - 8) {
      if (bytes[offset] !== 0xFF) { offset++; continue; }
      const marker = bytes[offset + 1];
      if (marker === 0xC0 || marker === 0xC2) {
        const height = (bytes[offset + 5] << 8) | bytes[offset + 6];
        const width = (bytes[offset + 7] << 8) | bytes[offset + 8];
        return { width, height };
      }
      const segmentLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
      offset += 2 + segmentLength;
    }
    return null;
  }
  return null;
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

function errorCode(error: unknown) {
  return (error instanceof Error ? error.message : "unknown_error").slice(0, 120);
}
```

- [ ] **Step 2: Type-check with Deno**

Run: `cd /Users/user/attune/supabase/functions/process-dating-photo && deno check index.ts`
Expected: no type errors.

- [ ] **Step 3: Deploy the function**

Run: `cd /Users/user/attune && supabase functions deploy process-dating-photo`
Expected: deploy succeeds.

- [ ] **Step 4: Provision the GOOGLE_VISION_API_KEY secret if not already set**

Run: `supabase secrets list | grep GOOGLE_VISION_API_KEY`
Expected: if missing, this is a deployment prerequisite — get a Google Cloud Vision API key from the user, then run `supabase secrets set GOOGLE_VISION_API_KEY=<key>`.

- [ ] **Step 5: Manual smoke test**

After Task 1's manual insert test leaves a `pending` job, invoke the worker directly:
```bash
curl -s -X POST "https://<project-ref>.supabase.co/functions/v1/process-dating-photo" \
  -H "Authorization: Bearer <service-role-key>" \
  -H "Content-Type: application/json" \
  -d '{}'
```
Expected: `{"success":true,"processed":1}` and `select moderation_state, rejection_reason from public.dating_profile_photos;` shows a terminal state (`approved`, `rejected`, or `needs_review`), never left at `pending`.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/process-dating-photo/index.ts
git commit -m "feat(dating): add process-dating-photo moderation worker"
```

---

### Task 5: `upload-dating-photo` edge function + shared client image preparer

**Files:**
- Create: `supabase/functions/upload-dating-photo/index.ts`
- Create: `lib/features/dating/domain/services/dating_image_preparer.dart`
- Test: `test/features/dating/dating_image_preparer_test.dart`

**Interfaces:**
- Consumes: `requireUser`, `HttpError`, `jsonResponse`, `serviceRoleClient` from `_shared/attune_auth.ts` (already exists).
- Produces (Dart): `PreparedDatingImage` (fields: `file, mimeType, byteSize`), `DatingImageRejected` (field: `code`), `DatingImagePreparer.prepare(String localPath) → Future<PreparedDatingImage>` — this is a near-identical port of `ChatImagePreparer` (`lib/features/chat/domain/services/chat_image_preparer.dart`) with two differences: max output size relaxed to 1.5MB (profile photos benefit from more detail than chat thumbnails) and no dedicated "chat-only" framing in its docstring, since this one is intentionally shared logic for dating photos specifically (kept as a separate class per file, not literally shared code, to avoid coupling the chat and dating features — see the note below).
- Produces (edge function): the `upload-dating-photo` function is actually a thin wrapper — in practice, uploads go client → Storage directly using the intent from `create_dating_photo_upload_intent` (Task 1), exactly like chat's `uploadChatImage`. This edge function exists only to smoke-test that the RPC-issued intent is independently reachable outside the Flutter client (useful for CI and for the manual test below); it is not on the client's hot path.

- [ ] **Step 1: Write the failing test for the image preparer**

```dart
// test/features/dating/dating_image_preparer_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProvider();

  test('rejects a missing file', () async {
    const preparer = DatingImagePreparer();
    expect(
      () => preparer.prepare('/nonexistent/path.jpg'),
      throwsA(
        isA<DatingImageRejected>().having((e) => e.code, 'code', 'media_missing'),
      ),
    );
  });

  test('rejects an undecodable file', () async {
    final path = p.join(Directory.systemTemp.path, 'not_an_image.jpg');
    final file = File(path);
    await file.writeAsBytes(Uint8List.fromList([0x00, 0x01, 0x02, 0x03]));
    addTearDown(() => file.deleteSync());

    const preparer = DatingImagePreparer();
    expect(
      () => preparer.prepare(path),
      throwsA(
        isA<DatingImageRejected>().having(
          (e) => e.code,
          'code',
          anyOf('media_type_unsupported', 'media_decode_failed'),
        ),
      ),
    );
  });

  test('prepares a valid JPEG under the size ceiling', () async {
    // Minimal valid 1x1 JPEG (magic bytes + SOI/EOI); real content isn't
    // required, only that the decoder + compressor pipeline completes.
    final path = p.join(Directory.systemTemp.path, 'tiny.jpg');
    final file = File(path);
    // A real 1x1 red JPEG, base64-decoded, to give the decoder something
    // genuinely valid to work with.
    const base64Jpeg =
        '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/2wBDAQMDAwQDBAgEBAgQCwkLEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBD/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAj/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=';
    await file.writeAsBytes(base64Decode(base64Jpeg));
    addTearDown(() => file.deleteSync());

    const preparer = DatingImagePreparer();
    final prepared = await preparer.prepare(path);
    expect(prepared.mimeType, 'image/jpeg');
    expect(prepared.byteSize, lessThanOrEqualTo(DatingImagePreparer.maxBytes));
    addTearDown(() => prepared.file.deleteSync());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/dating/dating_image_preparer_test.dart`
Expected: FAIL — `dating_image_preparer.dart` does not exist.

- [ ] **Step 3: Write the implementation**

This is a port of `lib/features/chat/domain/services/chat_image_preparer.dart` (read that file for the exact structure to copy) with `maxBytes` raised and class/error names renamed:

```dart
// lib/features/dating/domain/services/dating_image_preparer.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Result of preparing an image for the private dating-photo upload pipeline.
class PreparedDatingImage {
  const PreparedDatingImage({
    required this.file,
    required this.mimeType,
    required this.byteSize,
  });

  final File file;
  final String mimeType;
  final int byteSize;
}

/// Raised when an image cannot be made to meet the dating-photo upload
/// contract. The [code] is a coarse, content-free reason.
class DatingImageRejected implements Exception {
  const DatingImageRejected(this.code);
  final String code;

  @override
  String toString() => 'DatingImageRejected($code)';
}

/// Enforces the private-image upload contract on the client, before any
/// upload intent is requested — mirrors ChatImagePreparer
/// (lib/features/chat/domain/services/chat_image_preparer.dart) with a
/// higher output size ceiling appropriate for a profile photo rather than a
/// chat thumbnail. Kept as a separate class (not shared with chat) so the
/// two features' size/quality policies can diverge independently.
class DatingImagePreparer {
  const DatingImagePreparer();

  static const int maxBytes = 1536 * 1024; // 1.5 MB
  static const int maxSourceBytes = 25 * 1024 * 1024;
  static const int maxDimension = 2000;
  static const int maxDecodePixels = 60 * 1000 * 1000;

  static const _approvedInputMimes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  Future<PreparedDatingImage> prepare(String localPath) async {
    final source = File(localPath);
    if (!await source.exists()) {
      throw const DatingImageRejected('media_missing');
    }
    final sourceLength = await source.length();
    if (sourceLength <= 0) throw const DatingImageRejected('media_empty');
    if (sourceLength > maxSourceBytes) {
      throw const DatingImageRejected('media_too_large');
    }

    final bytes = await source.readAsBytes();
    final sniffedMime = _sniffMime(bytes);
    if (sniffedMime == null || !_approvedInputMimes.contains(sniffedMime)) {
      throw const DatingImageRejected('media_type_unsupported');
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const DatingImageRejected('media_decode_failed');
    if (decoded.width * decoded.height > maxDecodePixels) {
      throw const DatingImageRejected('media_dimensions_excessive');
    }

    final targetPath = await _tempTargetPath();

    try {
      for (final quality in const [85, 75, 65, 50, 35]) {
        final out = await FlutterImageCompress.compressAndGetFile(
          localPath,
          targetPath,
          quality: quality,
          minWidth: 1,
          minHeight: 1,
          keepExif: false,
          format: CompressFormat.jpeg,
        );
        if (out == null) continue;
        final outFile = File(out.path);
        final outSize = await outFile.length();
        if (outSize > 0 && outSize <= maxBytes) {
          return PreparedDatingImage(
            file: outFile,
            mimeType: 'image/jpeg',
            byteSize: outSize,
          );
        }
      }
    } catch (_) {
      // Fall through to the Dart-only path.
    }

    final resized = _resizeLongestEdge(decoded, maxDimension);
    final jpeg = img.encodeJpg(resized, quality: 65);
    if (jpeg.lengthInBytes <= maxBytes) {
      final outFile = File(targetPath);
      await outFile.writeAsBytes(jpeg, flush: true);
      return PreparedDatingImage(
        file: outFile,
        mimeType: 'image/jpeg',
        byteSize: jpeg.lengthInBytes,
      );
    }

    throw const DatingImageRejected('media_compress_failed');
  }

  img.Image _resizeLongestEdge(img.Image src, int longest) {
    final longestSide = src.width >= src.height ? src.width : src.height;
    if (longestSide <= longest) return src;
    if (src.width >= src.height) {
      return img.copyResize(src, width: longest);
    }
    return img.copyResize(src, height: longest);
  }

  Future<String> _tempTargetPath() async {
    Directory dir;
    try {
      dir = await getTemporaryDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }
    final name = 'dating_photo_${DateTime.now().microsecondsSinceEpoch}.jpg';
    return p.join(dir.path, name);
  }

  String? _sniffMime(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b[4] == 0x0D &&
        b[5] == 0x0A &&
        b[6] == 0x1A &&
        b[7] == 0x0A) {
      return 'image/png';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/dating/dating_image_preparer_test.dart`
Expected: PASS, 3/3 tests. If the `path_provider_platform_interface`/`plugin_platform_interface` test doubles aren't already dev dependencies, check `pubspec.yaml` first — if missing, add them (`flutter pub add --dev path_provider_platform_interface plugin_platform_interface`) before running.

- [ ] **Step 5: Write the smoke-test edge function**

```typescript
// supabase/functions/upload-dating-photo/index.ts
//
// Thin diagnostic wrapper confirming create_dating_photo_upload_intent is
// independently callable outside the Flutter client. The real upload path
// is client -> Supabase Storage directly, using the intent this RPC issues
// (see DatingRepository.createPhotoUploadIntent, Task 6).
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  HttpError,
  jsonResponse,
  requireUser,
} from "../_shared/attune_auth.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    const user = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const mimeType = typeof body.mime_type === "string" ? body.mime_type : null;
    if (!mimeType) throw new HttpError("mime_type is required", 400);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization")! } } },
    );

    const { data, error } = await supabase.rpc("create_dating_photo_upload_intent", {
      p_mime_type: mimeType,
    });
    if (error) throw new HttpError(error.message, 400);

    return jsonResponse({ intent: Array.isArray(data) ? data[0] : data, user_id: user.id });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    console.error("upload-dating-photo failed:", error instanceof Error ? error.name : typeof error);
    return jsonResponse({ error: "Could not create upload intent" }, 500);
  }
});
```

- [ ] **Step 6: Type-check and deploy**

Run: `cd /Users/user/attune/supabase/functions/upload-dating-photo && deno check index.ts`
Expected: no type errors.

Run: `cd /Users/user/attune && supabase functions deploy upload-dating-photo`
Expected: deploy succeeds.

- [ ] **Step 7: Commit**

```bash
git add lib/features/dating/domain/services/dating_image_preparer.dart
git add test/features/dating/dating_image_preparer_test.dart
git add supabase/functions/upload-dating-photo/index.ts
git commit -m "feat(dating): add client image preparer and upload-intent smoke-test function"
```

---

### Task 6: Flutter data layer — model, repository, providers

**Files:**
- Create: `lib/features/dating/data/models/dating_profile_photo.dart`
- Test: `test/features/dating/dating_profile_photo_model_test.dart`
- Modify: `lib/features/dating/data/repositories/dating_repository.dart`
- Modify: `lib/features/dating/presentation/providers/dating_providers.dart`

**Interfaces:**
- Consumes: `PreparedDatingImage`, `DatingImagePreparer`, `DatingImageRejected` from Task 5.
- Produces: `DatingProfilePhoto` (fields: `id, position, moderationState, rejectionReason, storageKey, createdAt`, factory `fromJson`, getters `isApproved`/`isPending`/`isRejected`/`needsReview`); `DatingRepository` additions: `Future<List<DatingProfilePhoto>> listPhotos()`, `Future<String> uploadPhoto({required String localPath, required int position})` (returns the new photo's id), `Future<void> deletePhoto(String photoId)`, `Future<String> submitVerificationSelfie({required String localPath})` (returns the resulting `verification_state`, including `'pending'` on an API-failure retry case — see Step 5), `Future<String> getVerificationState()`; new providers: `datingPhotosProvider` (`FutureProvider<List<DatingProfilePhoto>>`), `uploadDatingPhotoProvider` (`FutureProvider.family<String, ({String localPath, int position})>`), `deleteDatingPhotoProvider` (`FutureProvider.family<void, String>`), `submitVerificationSelfieProvider` (`FutureProvider.family<String, ({String localPath})>`, returns the same `verification_state` string), `datingVerificationStateProvider` (`FutureProvider<String>`).

- [ ] **Step 1: Write the failing test for the model**

```dart
// test/features/dating/dating_profile_photo_model_test.dart
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DatingProfilePhoto.fromJson parses an approved photo', () {
    final photo = DatingProfilePhoto.fromJson({
      'id': 'photo-1',
      'position': 1,
      'moderation_state': 'approved',
      'rejection_reason': null,
      'storage_key': 'dating-photos/abc.jpg',
      'created_at': '2026-08-02T10:00:00Z',
    });

    expect(photo.id, 'photo-1');
    expect(photo.position, 1);
    expect(photo.isApproved, isTrue);
    expect(photo.isPending, isFalse);
    expect(photo.rejectionReason, isNull);
  });

  test('DatingProfilePhoto.fromJson parses a rejected photo with a reason', () {
    final photo = DatingProfilePhoto.fromJson({
      'id': 'photo-2',
      'position': 2,
      'moderation_state': 'rejected',
      'rejection_reason': 'face_blurred',
      'storage_key': 'dating-photos/def.jpg',
      'created_at': '2026-08-02T10:00:00Z',
    });

    expect(photo.isRejected, isTrue);
    expect(photo.rejectionReason, 'face_blurred');
  });

  test('DatingProfilePhoto.fromJson parses needs_review', () {
    final photo = DatingProfilePhoto.fromJson({
      'id': 'photo-3',
      'position': 3,
      'moderation_state': 'needs_review',
      'rejection_reason': 'no_face_detected',
      'storage_key': 'dating-photos/ghi.jpg',
      'created_at': '2026-08-02T10:00:00Z',
    });

    expect(photo.needsReview, isTrue);
    expect(photo.isApproved, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/dating/dating_profile_photo_model_test.dart`
Expected: FAIL — `dating_profile_photo.dart` does not exist.

- [ ] **Step 3: Write the model**

```dart
// lib/features/dating/data/models/dating_profile_photo.dart
import 'package:equatable/equatable.dart';

class DatingProfilePhoto extends Equatable {
  final String id;
  final int position;
  final String moderationState; // pending | approved | rejected | needs_review
  final String? rejectionReason;
  final String storageKey;
  final DateTime createdAt;

  const DatingProfilePhoto({
    required this.id,
    required this.position,
    required this.moderationState,
    this.rejectionReason,
    required this.storageKey,
    required this.createdAt,
  });

  factory DatingProfilePhoto.fromJson(Map<String, dynamic> json) {
    return DatingProfilePhoto(
      id: json['id'] as String,
      position: json['position'] as int,
      moderationState: json['moderation_state'] as String,
      rejectionReason: json['rejection_reason'] as String?,
      storageKey: json['storage_key'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isApproved => moderationState == 'approved';
  bool get isPending => moderationState == 'pending';
  bool get isRejected => moderationState == 'rejected';
  bool get needsReview => moderationState == 'needs_review';

  @override
  List<Object?> get props => [id, position, moderationState, rejectionReason, storageKey, createdAt];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/dating/dating_profile_photo_model_test.dart`
Expected: PASS, 3/3 tests.

- [ ] **Step 5: Add repository methods**

Add to `lib/features/dating/data/repositories/dating_repository.dart` — add the import at the top and these methods inside the `DatingRepository` class (alongside the existing methods, following the file's established `_runIdempotent` pattern for every mutating call):

```dart
// Add near the top of the file, with the other imports:
import 'dart:io';
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';

// Add these methods inside class DatingRepository:

  Future<List<DatingProfilePhoto>> listPhotos() async {
    final response = await _supabase.rpc('list_dating_profile_photos');
    if (response is! List) {
      return const <DatingProfilePhoto>[];
    }
    return response
        .whereType<Map>()
        .map((row) => DatingProfilePhoto.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _createPhotoUploadIntent(String mimeType) async {
    final response = await _supabase.rpc(
      'create_dating_photo_upload_intent',
      params: {'p_mime_type': mimeType},
    );
    final row = response is List && response.isNotEmpty
        ? Map<String, dynamic>.from(response.first as Map)
        : Map<String, dynamic>.from(response as Map);
    return row;
  }

  Future<String> uploadPhoto({
    required String localPath,
    required int position,
  }) async {
    const preparer = DatingImagePreparer();
    final prepared = await preparer.prepare(localPath);

    final intent = await _createPhotoUploadIntent(prepared.mimeType);
    final storageKey = intent['storage_key'] as String;
    final bucket = intent['bucket'] as String;
    final intentId = intent['intent_id'] as String;

    await _supabase.storage.from(bucket).upload(
          storageKey,
          prepared.file,
          fileOptions: FileOptions(upsert: false, contentType: prepared.mimeType),
        );

    final response = await _supabase.rpc(
      'insert_dating_profile_photo',
      params: {'p_intent_id': intentId, 'p_position': position},
    );
    return response as String;
  }

  Future<void> deletePhoto(String photoId) async {
    await _runIdempotent(
      'delete_photo_$photoId',
      (key) => _supabase.rpc(
        'delete_dating_profile_photo',
        params: {'p_photo_id': photoId},
      ),
    );
  }

  /// Returns the resulting `verification_state` ('verified' | 'needs_review'
  /// | 'pending'). A 'pending' result means the Rekognition call itself
  /// failed (not a low-confidence match) — per spec §4 step 6, the caller
  /// should offer the user a retry rather than treating this as either
  /// success or failure.
  Future<String> submitVerificationSelfie({
    required String localPath,
  }) async {
    const preparer = DatingImagePreparer();
    final prepared = await preparer.prepare(localPath);
    final bytes = await File(prepared.file.path).readAsBytes();

    final response = await _supabase.functions.invoke(
      'verify-dating-profile',
      body: {
        'selfie_base64': base64Encode(bytes),
        'mime_type': prepared.mimeType,
      },
    );
    if (response.status != 200) {
      throw Exception('Verification request failed');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['verification_state'] as String? ?? 'pending';
  }

  Future<String> getVerificationState() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return 'unverified';
    final response = await _supabase
        .from('dating_profiles')
        .select('verification_state')
        .eq('user_id', userId)
        .maybeSingle();
    return response?['verification_state'] as String? ?? 'unverified';
  }
```

Note: `getVerificationState` reads `dating_profiles` directly via `.from(...).select(...)`, which requires this table to have a `SELECT` RLS policy scoped to the owner — check `20260811120000_dating_owner_read_grants.sql` (already in this repo per the session's own history of adding exactly this kind of owner-read grant) to confirm `dating_profiles` already has an owner-read policy before assuming this call will work; if it doesn't, add one in Task 1's migration instead of here.

Add `import 'dart:convert';` (`base64Encode`) and `import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';` to the repository file's imports.

- [ ] **Step 6: Add providers**

Add to `lib/features/dating/presentation/providers/dating_providers.dart`:

```dart
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';

final datingPhotosProvider = FutureProvider<List<DatingProfilePhoto>>((ref) async {
  return ref.read(datingRepositoryProvider).listPhotos();
});

final uploadDatingPhotoProvider = FutureProvider.family<
  String,
  ({String localPath, int position})
>((ref, params) async {
  final repository = ref.read(datingRepositoryProvider);
  final photoId = await repository.uploadPhoto(
    localPath: params.localPath,
    position: params.position,
  );
  ref.invalidate(datingPhotosProvider);
  ref.invalidate(datingVerificationStateProvider);
  return photoId;
});

final deleteDatingPhotoProvider = FutureProvider.family<void, String>((
  ref,
  photoId,
) async {
  await ref.read(datingRepositoryProvider).deletePhoto(photoId);
  ref.invalidate(datingPhotosProvider);
});

final submitVerificationSelfieProvider = FutureProvider.family<
  String,
  ({String localPath})
>((ref, params) async {
  final state = await ref
      .read(datingRepositoryProvider)
      .submitVerificationSelfie(localPath: params.localPath);
  ref.invalidate(datingVerificationStateProvider);
  return state;
});

final datingVerificationStateProvider = FutureProvider<String>((ref) async {
  return ref.read(datingRepositoryProvider).getVerificationState();
});
```

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd /Users/user/attune && flutter analyze lib/features/dating`
Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add lib/features/dating/data/models/dating_profile_photo.dart
git add test/features/dating/dating_profile_photo_model_test.dart
git add lib/features/dating/data/repositories/dating_repository.dart
git add lib/features/dating/presentation/providers/dating_providers.dart
git commit -m "feat(dating): add photo model, repository methods, and providers"
```

---

### Task 7: `verify-dating-profile` edge function

**Files:**
- Create: `supabase/functions/verify-dating-profile/index.ts`

**Interfaces:**
- Consumes: `compareFaces` from `_shared/aws_rekognition.ts` (Task 3); `requireUser`, `HttpError`, `jsonResponse`, `serviceRoleClient` from `_shared/attune_auth.ts`.
- Produces: an HTTP endpoint accepting `POST { selfie_base64: string, mime_type: string }` (matching `DatingRepository.submitVerificationSelfie`'s call in Task 6) → `{ verification_state: "verified" | "needs_review" }`. Writes only the enum + timestamp + method to `dating_profiles`; never persists the selfie, the comparison score, or any embedding.

- [ ] **Step 1: Write the implementation**

```typescript
// supabase/functions/verify-dating-profile/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  HttpError,
  jsonResponse,
  requireUser,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import { compareFaces } from "../_shared/aws_rekognition.ts";

const AWS_ACCESS_KEY_ID = Deno.env.get("AWS_REKOGNITION_ACCESS_KEY_ID");
const AWS_SECRET_ACCESS_KEY = Deno.env.get("AWS_REKOGNITION_SECRET_ACCESS_KEY");
const AWS_REGION = Deno.env.get("AWS_REKOGNITION_REGION") ?? "us-east-1";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    const user = await requireUser(req);
    if (!AWS_ACCESS_KEY_ID || !AWS_SECRET_ACCESS_KEY) {
      throw new Error("missing_rekognition_credentials");
    }

    const body = await req.json().catch(() => ({}));
    const selfieBase64 = typeof body.selfie_base64 === "string" ? body.selfie_base64 : null;
    if (!selfieBase64) throw new HttpError("selfie_base64 is required", 400);

    const supabase = serviceRoleClient();

    // NOTE: verification eligibility requires at least one approved photo —
    // enforce this before spending an API call.
    const { data: approvedPhotos, error: photosError } = await supabase
      .from("dating_profile_photos")
      .select("storage_key")
      .eq("user_id", user.id)
      .eq("moderation_state", "approved");
    if (photosError) throw photosError;
    if (!approvedPhotos || approvedPhotos.length === 0) {
      throw new HttpError("At least one approved photo is required before verification", 400);
    }

    await supabase
      .from("dating_profiles")
      .update({ verification_state: "pending" })
      .eq("user_id", user.id);

    const selfieBytes = base64ToBytes(selfieBase64);

    let allMatched = true;
    try {
      for (const photo of approvedPhotos) {
        const { data: targetFile, error: downloadError } = await supabase.storage
          .from("dating-profile-photos")
          .download(photo.storage_key);
        if (downloadError || !targetFile) throw new Error("target_photo_missing");

        const targetBytes = new Uint8Array(await targetFile.arrayBuffer());
        const result = await compareFaces({
          sourceImageBytes: selfieBytes,
          targetImageBytes: targetBytes,
          accessKeyId: AWS_ACCESS_KEY_ID,
          secretAccessKey: AWS_SECRET_ACCESS_KEY,
          region: AWS_REGION,
        });
        // Only the boolean is read here. `result.similarity` is intentionally
        // never referenced beyond this line, never logged, and never written
        // to any table — per spec §4's architectural boundary.
        if (!result.matched) {
          allMatched = false;
          break;
        }
      }
    } catch (compareError) {
      // API failure (not a low-confidence result): retry-eligible, land in
      // pending rather than a false verified/needs_review verdict.
      console.error("verify-dating-profile compare failed:", compareError instanceof Error ? compareError.message : "unknown");
      return jsonResponse({ verification_state: "pending", retry: true }, 200);
    }

    const finalState = allMatched ? "verified" : "needs_review";
    await supabase
      .from("dating_profiles")
      .update({
        verification_state: finalState,
        verification_method: "selfie_self_consistency_v1",
        verified_at: finalState === "verified" ? new Date().toISOString() : null,
      })
      .eq("user_id", user.id);

    return jsonResponse({ verification_state: finalState });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    console.error("verify-dating-profile failed:", error instanceof Error ? error.name : typeof error);
    return jsonResponse({ error: "Could not complete verification" }, 500);
  }
});

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
```

- [ ] **Step 2: Type-check with Deno**

Run: `cd /Users/user/attune/supabase/functions/verify-dating-profile && deno check index.ts`
Expected: no type errors.

- [ ] **Step 3: Deploy and provision AWS secrets**

Run: `supabase secrets list | grep AWS_REKOGNITION`
Expected: if missing, get AWS credentials for a Rekognition-scoped IAM user from the user, then:
```bash
supabase secrets set AWS_REKOGNITION_ACCESS_KEY_ID=<key-id>
supabase secrets set AWS_REKOGNITION_SECRET_ACCESS_KEY=<secret>
supabase secrets set AWS_REKOGNITION_REGION=us-east-1
```

Run: `cd /Users/user/attune && supabase functions deploy verify-dating-profile`
Expected: deploy succeeds.

- [ ] **Step 4: Manual smoke test proving no score is persisted**

After a real verification call (via the app or a direct curl with a real selfie + an approved photo present), run:
```sql
select verification_state, verification_method, verified_at from public.dating_profiles where user_id = '<test-user-id>';
```
Expected: exactly these three columns populated, no similarity/score column exists anywhere in the schema for this table (confirmed by Task 1's migration containing no such column) — this is the concrete verification of spec §4's core architectural boundary.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/verify-dating-profile/index.ts
git commit -m "feat(dating): add verify-dating-profile self-consistency check"
```

---

### Task 8: Screens — photo management and verification

**Files:**
- Create: `lib/features/dating/presentation/screens/dating_photos_screen.dart`
- Create: `lib/features/dating/presentation/screens/dating_verification_screen.dart`
- Modify: `lib/app/routing/app_router.dart` (add routes)

**Interfaces:**
- Consumes: `datingPhotosProvider`, `uploadDatingPhotoProvider`, `deleteDatingPhotoProvider`, `submitVerificationSelfieProvider`, `datingVerificationStateProvider` (Task 6); `DatingProfilePhoto` (Task 6); `DatingImagePreparer`/`DatingImageRejected` (Task 5); app-wide `ImagePickerService` (`lib/core/services/media/image_picker_service.dart`, already exists — method `pickImage({required bool fromCamera, bool crop, CropAspectRatio? cropRatio, bool lockAspectRatio})`); `AppButton`, `EmptyStateWidget` (already used throughout this codebase's other screens).
- Produces: `DatingPhotosScreen` (`ConsumerWidget`, no constructor args — shows up to 4 photo slots, upload/delete, per-photo status/rejection copy), `DatingVerificationScreen` (`ConsumerStatefulWidget`, no constructor args — disclosure text, camera-only capture button, submit).

- [ ] **Step 1: Write `DatingPhotosScreen`**

```dart
// lib/features/dating/presentation/screens/dating_photos_screen.dart
import 'package:attune/core/services/media/image_picker_service.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';
import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:attune/features/dating/presentation/providers/dating_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingPhotosScreen extends ConsumerStatefulWidget {
  const DatingPhotosScreen({super.key});

  @override
  ConsumerState<DatingPhotosScreen> createState() => _DatingPhotosScreenState();
}

class _DatingPhotosScreenState extends ConsumerState<DatingPhotosScreen> {
  final _imagePicker = ImagePickerService();
  final Set<int> _uploadingPositions = {};

  Future<void> _addPhoto(int position) async {
    final picked = await _imagePicker.pickImage(
      fromCamera: false,
      crop: true,
      lockAspectRatio: true,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingPositions.add(position));
    try {
      await ref.read(
        uploadDatingPhotoProvider((
          localPath: picked.path,
          position: position,
        )).future,
      );
    } on DatingImageRejected catch (rejected) {
      if (!mounted) return;
      context.showErrorSnackbar(_rejectionMessage(rejected.code));
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not upload that photo. Please try again.');
    } finally {
      if (mounted) setState(() => _uploadingPositions.remove(position));
    }
  }

  Future<void> _deletePhoto(String photoId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this photo?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(deleteDatingPhotoProvider(photoId).future);
  }

  String _rejectionMessage(String code) {
    switch (code) {
      case 'media_type_unsupported':
        return 'That file type isn\'t supported. Choose a JPG, PNG, or WebP image.';
      case 'media_too_large':
      case 'media_compress_failed':
        return 'That image is too large. Try a smaller one.';
      case 'media_decode_failed':
      case 'media_dimensions_excessive':
        return 'That image couldn\'t be read. Try a different one.';
      default:
        return 'That image couldn\'t be uploaded.';
    }
  }

  String _photoStatusMessage(DatingProfilePhoto photo) {
    if (photo.isPending) return 'Reviewing your photo...';
    if (photo.needsReview) return 'This photo needs a closer look — we\'ll follow up.';
    if (photo.isRejected) {
      switch (photo.rejectionReason) {
        case 'face_blurred':
          return 'This photo looks blurry. Try a clearer shot.';
        case 'face_underexposed':
          return 'This photo is too dark. Try better lighting.';
        case 'face_too_small':
          return 'Your face is too small in this photo. Try getting closer.';
        case 'image_too_small':
          return 'This image is too low-resolution. Try a larger photo.';
        case 'adult_content_detected':
        case 'violent_content_detected':
        case 'racy_content_detected':
          return 'This photo doesn\'t meet our content guidelines.';
        default:
          return 'This photo couldn\'t be approved.';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(datingPhotosProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Your photos',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: photosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: ErrorStateWidget(
            title: 'Something went wrong',
            subtitle: 'We couldn\'t load your photos right now. Please try again in a moment.',
          ),
        ),
        data: (photos) {
          final byPosition = {for (final p in photos) p.position: p};
          return Padding(
            padding: EdgeInsets.all(Spacing.md.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add 1 to 4 photos. Clear, recent photos of just you work best.',
                  style: textTheme.bodyMedium,
                ),
                Gap(Spacing.lg.h),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: Spacing.md.w,
                  mainAxisSpacing: Spacing.md.h,
                  children: List.generate(4, (index) {
                    final position = index + 1;
                    final photo = byPosition[position];
                    final isUploading = _uploadingPositions.contains(position);

                    if (isUploading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (photo == null) {
                      return InkWell(
                        onTap: () => _addPhoto(position),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                          ),
                          child: const Center(child: Icon(Icons.add_a_photo_outlined)),
                        ),
                      );
                    }
                    return GestureDetector(
                      onTap: () => _deletePhoto(photo.id),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              photo.isApproved ? Icons.check_circle_outline : Icons.hourglass_empty,
                            ),
                            if (!photo.isApproved) ...[
                              Gap(Spacing.xs.h),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
                                child: Text(
                                  _photoStatusMessage(photo),
                                  style: textTheme.labelSmall,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Write `DatingVerificationScreen`**

```dart
// lib/features/dating/presentation/screens/dating_verification_screen.dart
import 'package:attune/core/services/media/image_picker_service.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/dating/presentation/providers/dating_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingVerificationScreen extends ConsumerStatefulWidget {
  const DatingVerificationScreen({super.key});

  @override
  ConsumerState<DatingVerificationScreen> createState() =>
      _DatingVerificationScreenState();
}

class _DatingVerificationScreenState extends ConsumerState<DatingVerificationScreen> {
  final _imagePicker = ImagePickerService();
  bool _isSubmitting = false;

  Future<void> _captureAndSubmit() async {
    // Camera only — no gallery import, per spec §4.
    final picked = await _imagePicker.pickImage(
      fromCamera: true,
      crop: true,
      lockAspectRatio: true,
    );
    if (picked == null || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final state = await ref.read(
        submitVerificationSelfieProvider((localPath: picked.path)).future,
      );
      if (!mounted) return;
      if (state == 'pending') {
        // The Rekognition call itself failed (not a low-confidence match) —
        // spec §4 step 6 requires a retry offer here, not a false success.
        context.showErrorSnackbar(
          'We couldn\'t complete verification just now. Please try again.',
        );
        return;
      }
      // Both 'verified' and 'needs_review' are genuine completed outcomes
      // from the caller's point of view — neither is shown as a badge
      // anywhere (spec §6), so the copy stays identical either way.
      context.showSuccessSnackbar('Verification submitted.');
      context.pop();
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not submit your photo just now. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Confirm your photos',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.md.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We compare your verification selfie to your profile photos to confirm '
              'they\'re consistent. The comparison happens once, the result is a '
              'simple pass/fail, and it\'s never used to affect who you\'re matched with.',
              style: textTheme.bodyMedium,
            ),
            const Spacer(),
            AppButton(
              label: _isSubmitting ? 'Submitting...' : 'Take a photo to confirm',
              onPressed: _isSubmitting ? null : _captureAndSubmit,
              size: ButtonSize.large,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Register routes**

In `lib/app/routing/app_router.dart`, add the import near the other dating imports and two `GoRoute`s near the other dating routes:

```dart
import 'package:attune/features/dating/presentation/screens/dating_photos_screen.dart';
import 'package:attune/features/dating/presentation/screens/dating_verification_screen.dart';
```

```dart
      GoRoute(
        path: RouteNames.datingPhotos,
        name: 'datingPhotos',
        builder: (context, state) => const DatingPhotosScreen(),
      ),
      GoRoute(
        path: RouteNames.datingVerification,
        name: 'datingVerification',
        builder: (context, state) => const DatingVerificationScreen(),
      ),
```

Add the two route name constants to `RouteNames` alongside the other `dating*` constants:
```dart
  static const String datingPhotos = '/datingPhotos';
  static const String datingVerification = '/datingVerification';
```

- [ ] **Step 4: Wire an entry point from the existing dating profile screen**

In `lib/features/dating/presentation/screens/dating_profile_screen.dart`, add a button that navigates to the photos screen (exact placement depends on that screen's current layout — read the file first, then add near the existing profile-field editing controls):
```dart
AppButton(
  label: 'Manage photos',
  onPressed: () => context.pushNamed('datingPhotos'),
  variant: ButtonVariant.outline,
),
```

- [ ] **Step 5: Run `flutter analyze`**

Run: `cd /Users/user/attune && flutter analyze lib/features/dating lib/app/routing/app_router.dart`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/dating/presentation/screens/dating_photos_screen.dart
git add lib/features/dating/presentation/screens/dating_verification_screen.dart
git add lib/app/routing/app_router.dart
git add lib/features/dating/presentation/screens/dating_profile_screen.dart
git commit -m "feat(dating): add photo management and verification screens"
```

---

## Post-implementation manual verification (not a task — a checklist for the final reviewer)

- [ ] Upload a real photo of a person via the app; confirm it moves from "Reviewing..." to approved within a reasonable time (Task 1's `trigger_enqueue_dating_photo_processing` fires `process-dating-photo` automatically on insert, mirroring `enqueue_chat_media_processing` — this covers the normal path). Also confirm a periodic operator-configured `pg_cron` sweep exists calling `process-dating-photo` with no `photo_id` (to catch any 'pending' job whose insert-time HTTP call silently failed, e.g. a cold start) — this plan builds the worker and the insert-time trigger, but the periodic catch-all cron schedule itself is an operator deploy step outside this plan's scope, same as this repo's existing `recover_stale_chat_worker_leases`-style sweeps.
- [ ] Upload an obviously non-human photo (a landscape); confirm it lands in `needs_review`, not silently `approved` or `rejected`.
- [ ] Upload a blurry photo; confirm the specific "looks blurry" rejection copy shows, not a generic message.
- [ ] Attempt a 5th photo upload; confirm the UI/RPC rejects it.
- [ ] Complete verification with a selfie that genuinely matches the uploaded photos; confirm `verification_state` becomes `verified` and no badge appears anywhere in the UI.
- [ ] Complete verification with a selfie of a different person (if testable); confirm `verification_state` becomes `needs_review`, not silently rejected or silently approved.
- [ ] Replace an approved photo after verification; confirm `verification_state` reverts to `needs_review` per spec §4 step 5.
- [ ] Confirm `dating_feature_snapshots.features` never contains anything photo- or verification-derived, by inspecting a real snapshot row after a candidate-generation run.
