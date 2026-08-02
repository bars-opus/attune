# Dating Mode Photo Upload, Moderation & Verification — Design Spec

**Status:** Approved, ready for implementation planning
**Author:** Claude (Sonnet 5) with deep-analysis research by Claude (Opus)
**Date:** 2026-08-02

## 1. Problem statement

`DATING_MODE_SPEC.md` §11 already defines `dating_profile_photos` (id, user_id, storage_key, position, moderation_state, created_at — live in `20260703203000_dating_mode_contract_hardening.sql`) and requires (§4.3, §5): photos moderated before display, a pending/failed photo never entering candidate payloads, and photos never used as a ranking signal. None of this is implemented — there is no upload UI, no moderation worker, and no way to verify an uploaded photo actually depicts the uploading user.

This spec designs: (1) content moderation via Google Cloud Vision (already available to this project), (2) photo-quality gating using the same Vision call, (3) a self-consistency identity check via AWS Rekognition `CompareFaces` to counter catfishing, and (4) the upload/review UI and async worker pipeline tying it together — reusing this codebase's existing outbox/claim-jobs pattern (`process-chat-media`, `claim_chat_media_jobs`) rather than inventing a new one.

## 2. Governing constraints (from `DATING_MODE_SPEC.md`, non-negotiable)

- §4.3: "Never use photos, face embeddings, attractiveness, skin tone, or image-derived attributes in ranking." Verification must be a hard eligibility filter (pass/fail), never a signal that reaches `dating_feature_snapshots.features` or influences score. No similarity score or embedding is ever persisted — only a boolean/enum result.
- §5: "Require moderation before display. A pending or failed photo cannot enter candidate payloads." The gate is enforced at candidate-generation read time, not at upload time — async moderation latency is acceptable and does not block the upload flow.
- §4.3: "Strip EXIF and location metadata before upload... Use random server-safe object keys." Applies identically here.
- §2: Client cannot set `moderation_state`, verification state, candidate rank, score, or any trusted field directly — every state transition is server-authoritative.
- Radical disclosure (soul-level pattern already used throughout this codebase): before capturing a verification selfie, the user sees exactly what happens to it, in plain language, before consenting.
- No dark patterns: rejections get specific, actionable copy, never a bare "rejected." Face-detection or comparison failures route to human review, never silent auto-reject — false negatives on legitimate photos (angled shots, lighting) are expected and must not silently destroy a real user's content.

## 3. Content & quality moderation (Google Cloud Vision)

One `images:annotate` call per uploaded photo, requesting both `SAFE_SEARCH_DETECTION` and `FACE_DETECTION` features together (same request, no extra cost tier).

**Pre-Vision checks (free, no API call, run first):**
- File decodes as a valid image (reject polyglot/corrupt files).
- Minimum dimensions 600×600px.

**Vision-derived checks (one call):**
- SafeSearch: `adult`, `violence`, `racy` likelihood must each be below a configured threshold (default: reject at `LIKELY`/`VERY_LIKELY`; `POSSIBLE` also rejects for `adult`/`violence` given the trust-critical context). `medical` and `spoof` are logged but not auto-rejecting in v1 — low relevance to this photo type, revisit if abuse patterns emerge.
- Face presence: at least one `faceAnnotations` entry with `detectionConfidence` ≥ 0.7. No face detected → `needs_review`, not auto-reject (per the false-negative caveat in §2).
- Face not blurred: `blurredLikelihood` ≤ `POSSIBLE`.
- Face not underexposed: `underExposedLikelihood` ≤ `POSSIBLE`.
- Face large enough in frame: `fdBoundingPoly` area ÷ full image area ≥ 6%.

All thresholds live in a server-side config row (not hardcoded), since they will need retuning against real uploads.

**Explicitly deferred, with reasons (do not build in v1):**
- Whole-image blur (Laplacian variance or similar): the face-level `blurredLikelihood` field already covers the part of the image that matters; a whole-image score would penalize sharp faces against soft backgrounds.
- General "lighting quality" beyond underexposure: no Vision field supports this without drifting into attractiveness judgment, which §4.3 forbids in spirit.
- Framing/composition rules: no API support, high false-reject risk, not worth building.
- `LABEL_DETECTION`/`OBJECT_LOCALIZATION` for friendlier rejection copy (e.g. "this looks like a photo of a dog"): purely a UX nicety since face-confidence already carries the pass/fail decision. Revisit only if support volume shows generic-rejection confusion.

## 4. Identity verification (AWS Rekognition `CompareFaces`)

**What this is, stated precisely for both the spec and the user-facing copy:** a self-consistency check — "are all of this profile's photos the same person" — not government ID verification and not liveness detection (proof the selfie was captured live, not itself a photo-of-a-photo). True liveness is explicitly deferred to v2; see §7.

**Flow:**
1. During Dating Mode profile setup, after at least one photo is approved, the user is shown plain-language disclosure (§6) and then captures a **verification selfie using the in-app camera only** — no gallery import allowed, since that would let a scammer submit a second stolen photo as the "selfie."
2. The selfie is compared via `CompareFaces` against every currently-approved profile photo.
3. High similarity across all comparisons → `verified`.
4. Any low-similarity comparison → `needs_review`. The profile is **not discoverable** (excluded from candidate generation) until a human resolves the review, one way or the other. Never auto-rejected outright — mismatches can be legitimate (old photo, lighting, appearance change) as well as fraudulent.
5. Re-verification is required whenever a new photo is added or an existing one is replaced (new photo must also match the verification selfie on file, or verification reverts to `needs_review`).
6. If the Rekognition call itself fails (timeout, transient error, quota) rather than returning a low-confidence result, the outcome is `pending` with a retry — identical to the photo-moderation worker's retry convention (§9) — never a silent permanent hold and never a fallback to `verified`. After `MAX_ATTEMPTS`, a persistently-failing verification also lands in `needs_review` (a technical failure and a genuine mismatch are handled by the same human queue, distinguished by `rejection_reason`/an equivalent failure-code field so reviewers can tell the two apart).

**Resolution path for `needs_review` (moderator action, not yet built as UI in this spec, but the data model must support it now):** a moderator sets `dating_profiles.verification_state` to `verified` or back to `unverified` (prompting the user to retry) via a service-role-only RPC (`resolve_dating_verification_review(p_user_id, p_outcome)`), analogous to the existing moderation-resolution pattern used elsewhere in this codebase for forum/opinion reports. The actual moderator-facing screen is out of scope for this spec (no admin UI exists yet in this codebase for any moderation queue) — building the RPC and the queryable `needs_review` list is in scope; the review UI itself is a fast-follow noted as a known gap, not silently assumed away.

**Architectural boundary — the most important constraint in this spec:** the comparison result stored in the database is a bare enum (`unverified | pending | verified | needs_review`) plus a timestamp and `verification_method` (set to `'selfie_self_consistency_v1'` so a future v2 liveness upgrade can be distinguished from re-verified legacy rows). The similarity score itself, and any face embedding either vendor's API returns, is used only in-memory for the pass/fail decision inside the edge function and is never written to any table, never logged, and never reaches `dating_feature_snapshots` or any other ranking input. This is enforced by the edge function's own code discipline (it has no code path that writes a score anywhere) and verified by a test asserting no numeric similarity value appears in any persisted row.

Verification is a **hard eligibility filter** only — a verified user is not ranked higher than an unverified-but-approved one; verification only gates whether the profile is discoverable at all. This distinction matters: letting verification nudge rank would smuggle an image-derived signal into ranking through the back door, violating §4.3 without technically storing an embedding.

## 5. Photo count

**Minimum 1, maximum 4.** A `dating_profiles` row can exist with zero photos (satisfying §4.1's "Optional" framing for the profile draft state), but the profile does not enter candidate generation until it has at least one `approved` photo — reconciling "optional" with §5's "enough approved profile content to render safely."

Four, not the market-standard six (Hinge/Bumble), because `DATING_MODE_SPEC.md` §4.2 places the Alignment preview before any photo in the introduction UI — photos are deliberately secondary to psychological alignment. A six-photo gallery would quietly invert that hierarchy into photo-first curation. Four is enough to serve as a real anti-catfish signal (multiple photos to compare) while staying visibly subordinate to the Alignment preview.

## 6. Verification UX — no visible badge

Verification status is **never displayed as a trust badge, checkmark, or "Verified" label anywhere in the product.** It is purely an internal eligibility gate. A visible badge risks users over-trusting a check that is a limited self-consistency comparison, not identity verification — the same reasoning `DATING_MODE_SPEC.md` §4.2 already applies to alignment percentages (shown as bands, not false-precision numbers, to avoid overclaiming certainty).

Before capturing the verification selfie, the disclosure screen states plainly (mirroring this codebase's existing radical-disclosure copy pattern):

> "We compare your verification selfie to your profile photos to confirm they're consistent. The comparison happens once, the result is a simple pass/fail, and it's never used to affect who you're matched with."

## 7. Explicitly deferred to v2

- **True liveness detection** (proving the selfie was captured live, not replayed from another photo or video) — e.g. AWS Rekognition Face Liveness or a dedicated KYC vendor (Persona, Onfido, iProov, FaceTec). Deferred because: the residual risk this leaves open (a scammer submitting a full stolen photo set of one victim, including as the "selfie") is narrower than what v1 already closes (a scammer submitting one stolen photo as a single profile image); liveness needs a client SDK and a real capture-challenge UX; and it is a strictly additive upgrade — it slots in as a step before the same `CompareFaces` call, so `verification_method` versioning already anticipates it.
- **Government ID / KYC-grade identity verification.** Out of scope entirely for this app's current trust model; self-consistency is proportionate to the risk this feature is actually mitigating (stolen-photo catfishing), not identity fraud generally.
- **`LABEL_DETECTION`-driven friendlier rejection copy** (§3).
- **Whole-image blur/lighting scoring** (§3).

## 8. Data model

Extends the existing live `dating_profile_photos` table (no breaking change) and adds verification state to `dating_profiles`.

```sql
-- Additive columns on the existing dating_profile_photos table
ALTER TABLE public.dating_profile_photos
  ADD COLUMN IF NOT EXISTS rejection_reason text,
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
  ADD COLUMN IF NOT EXISTS attempts smallint NOT NULL DEFAULT 0;

-- moderation_state CHECK already allows ('pending','approved','rejected');
-- extend to add the human-review state:
ALTER TABLE public.dating_profile_photos
  DROP CONSTRAINT IF EXISTS dating_profile_photos_moderation_state_check;
ALTER TABLE public.dating_profile_photos
  ADD CONSTRAINT dating_profile_photos_moderation_state_check
  CHECK (moderation_state IN ('pending', 'approved', 'rejected', 'needs_review'));

-- Verification state lives on the profile (per-user), not per-photo
ALTER TABLE public.dating_profiles
  ADD COLUMN IF NOT EXISTS verification_state text NOT NULL DEFAULT 'unverified'
    CHECK (verification_state IN ('unverified', 'pending', 'verified', 'needs_review')),
  ADD COLUMN IF NOT EXISTS verification_method text,
  ADD COLUMN IF NOT EXISTS verified_at timestamptz;

-- New outbox table, mirroring message_media_processing_outbox's shape
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

-- Verification selfie is never persisted as a durable row referencing storage;
-- it is uploaded to a short-lived private path, compared, then deleted by the
-- same edge function invocation. No table stores the selfie's storage_key
-- beyond the single request's lifetime.
```

Candidate-generation queries filter `dating_profile_photos.moderation_state = 'approved'` and `dating_profiles.verification_state = 'verified'` server-side (RPC/view), never client-enforced, per §2.

## 9. Edge functions

**`upload-dating-photo`** (user-JWT function): validates ownership, position (1-4), enqueues `dating_photo_moderation_outbox` row transactionally with the photo insert. Strips EXIF/normalizes orientation before storing to the private `dating-profile-photos` bucket with an opaque object key.

**`process-dating-photo`** (service-role worker, mirrors `process-chat-media`): claims jobs via a new `claim_dating_photo_jobs` RPC (identical `SELECT ... FOR UPDATE SKIP LOCKED` shape to `claim_chat_media_jobs`), runs the Vision checks from §3, writes `moderation_state`/`rejection_reason`/`reviewed_at`, and finishes the outbox row into `done` or `dead_letter` (`MAX_ATTEMPTS = 5`, identical retry convention).

**`verify-dating-profile`** (user-JWT function): accepts the verification selfie upload, runs `CompareFaces` against every currently-approved photo for that user, writes only the enum result to `dating_profiles.verification_state`, and deletes the selfie and any in-memory embedding before returning. Never reads or writes `dating_feature_snapshots`. On a Rekognition API failure (as opposed to a successful low-similarity result), the function sets `pending` and the client is told to retry with backoff, matching §4 step 6 — the function itself does not implement the outbox/retry-count bookkeeping (there is no durable job here, since the selfie is never persisted), so retry is client-driven up to a small fixed number of attempts, after which the client directs the user to a "having trouble verifying" state that still lands them in `needs_review` via a direct RPC call rather than leaving them stuck silently.

A `recover_stale_dating_photo_jobs` RPC mirrors the existing `recover_stale_chat_worker_leases` 5-minute stale-processing-lease recovery pattern.

## 10. Testing evidence expected at implementation time

- Unit tests for the Vision-response-to-decision mapping (§3 thresholds), including the no-face-detected → `needs_review` (not reject) case.
- A test proving `verify-dating-profile`'s response and every row it writes contain no numeric similarity score and no embedding — only the enum, timestamp, and method string.
- An integration test proving candidate-generation excludes profiles with `verification_state != 'verified'` or zero `approved` photos.
- A test proving photo position is capped at 4 and the upload function rejects a 5th.
- Widget tests for the disclosure screen (must show the exact consent copy before allowing selfie capture) and the review/rejection states (specific copy per rejection reason, never a bare "rejected").
