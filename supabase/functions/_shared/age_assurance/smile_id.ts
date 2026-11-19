// supabase/functions/_shared/age_assurance/smile_id.ts
// Spec 2 W4a (§3.3.5): the real ID-document provider, Smile ID (Ghana
// Card, passports, UK driving licence). The device's Smile ID capture
// submits the document and selfie under the job this returns (no Attune
// user id is sent: the job is named after the verification session); the
// server reads the result with a signed job_status call. Only the outcome,
// the face-match answer and the document's date of birth are read (the
// date is compared with the declared one and dropped; never logged or
// stored). Images are never requested (image_links false). The response
// fields read here are checked against the vendor's sandbox at the W4 gate
// (owner checklist).
//
// Spec 2 W4 final (I-2 ruling; replaces Task 2 fix round 1's reading of
// Actions alone): the job is classified by its ResultCode, because Smile
// ID reports Verify_Document "Failed" for fixable answers too (unreadable,
// expired, unsupported). A failed ID check is final (R-13), so "fail" is
// only a document judged not genuine or a confirmed document-face
// mismatch; fixable answers are "retry" (never final); an ID that shows
// under 18 is "minor" (Spec 1's hold, R-8); anything not recognised is
// "pending" (a person checks). Never a pass but 0810.
//
// Source: Smile ID's documentation, Document Verification (job type 6),
// "Product-Specific Result Codes", "General Failure Result Codes", "Human
// Review Rejection Result Codes" and "Actions":
//   https://legacy-docs.usesmileid.com/products/for-individuals-kyc/document-verification/document-verification
// (read 2026-11-19). 0810 "Document Verified"; 0811 "Unable to Verify
// Document - <reason>" (the image was usable, verification failed; the
// reasons listed below, and "... After Human Review (<reason>)"); 0812
// "Unable to verify Document - <reason>" (the document could not be
// classified, or an invalid image); 0816 Unsupported Document; 0817
// "Approved with Attention - Document is Expired | Photocopied Document |
// Suspicious Device Detected"; 1014 Unsupported ID Type; 0001 Data Invalid
// / images corrupt or unusable / System Error; 0903 Zip Corrupt.
// Selfie_To_ID_Card_Compare reads Completed | Under Review | Not
// Applicable (never Passed); Human_Review_Compare Passed | Failed | Unable
// to Determine | Not Applicable.
// OWNER SANDBOX CHECK (before flag-on), each failing closed until then:
// the exact ResultText of each 0811 reason (matched by phrase below; a
// phrase that doesn't match is "pending"); that an 0811 MRZ/OCR mismatch
// ("the information on document is inconsistent") is a forgery signal or
// a misread (pending until known); that 0810 always carries
// Selfie_To_ID_Card_Compare "Completed" when the selfie matched; that
// ResultCode arrives as a string ("0810"); that an under-18 0811 is
// Smile's own 18 threshold.
import { calendarDate, type IdDocumentProvider, type IdResult } from "./types.ts";

/// Spec 2 W4 final (I-2): 0811 reasons, by the documented phrase.
const FACE_MISMATCH = /selfie did not match the photo on (the )?document/i;
const NOT_GENUINE = [/security features were missing/i, /\(potential fraud attempt\)/i];
const UNDER_18 = /subject is under 18 years old/i;
const FIXABLE_0811 = [/selfie failed liveness/i, /wrong document type/i,
  /\((cropped document|not a document|unreadable document|unsupported document|wrong document type)\)/i];
/// Codes whose answer is fixable with a new capture (never final).
const FIXABLE_CODES = new Set(["0812", "0816", "1014", "0001", "0903"]);
const FIXABLE_0817 = [/document is expired/i, /photocopied document/i];

const outcome = (status: IdResult["status"]): IdResult => ({ status, dob: null, faceMatch: null });

/// Spec 2 W4 final (I-2): a job_status answer as an IdResult. Only the
/// code, the reason's phrase, the two compares and the date are read; the
/// text is never kept, logged or passed on.
export function classifySmileIdJob(answer: unknown): IdResult {
  const r = (answer ?? {}) as Record<string, unknown>;
  if (r.job_complete !== true) return outcome("pending");
  const result = (r.result ?? {}) as Record<string, unknown>;
  const actions = (result.Actions ?? {}) as Record<string, unknown>;
  const code = typeof result.ResultCode === "string" ? result.ResultCode : null;
  const text = typeof result.ResultText === "string" ? result.ResultText : "";
  const human = actions.Human_Review_Compare;
  if (code === "0810") {
    // The face was compared: by Smile's system (Completed, no person
    // involved) or by its person (Passed). Anything else waits.
    const faceDone = human === "Passed"
      || ((human === undefined || human === "Not Applicable") && actions.Selfie_To_ID_Card_Compare === "Completed");
    if (r.job_success !== true || actions.Verify_Document !== "Passed" || !faceDone) return outcome("pending");
    return { status: "pass", dob: calendarDate(result.DOB), faceMatch: true };
  }
  if (code === "0811") {
    if (human === "Failed" || FACE_MISMATCH.test(text) || NOT_GENUINE.some((p) => p.test(text))) return outcome("fail");
    if (UNDER_18.test(text)) return outcome("minor");
    if (FIXABLE_0811.some((p) => p.test(text))) return outcome("retry");
    return outcome("pending");
  }
  if (code !== null && FIXABLE_CODES.has(code)) return outcome("retry");
  if (code === "0817" && FIXABLE_0817.some((p) => p.test(text))) return outcome("retry");
  return outcome("pending");
}

export interface SmileIdConfig {
  partnerId: string;
  apiKey: string;
  baseUrl: string;
  fetch?: typeof fetch;
  now?: () => Date;
}

export const SMILE_ID_SANDBOX = "https://testapi.smileidentity.com";
export const SMILE_ID_LIVE = "https://api.smileidentity.com";

export function smileIdConfigFrom(env: (name: string) => string | undefined, live: boolean, f?: typeof fetch): SmileIdConfig | null {
  const partnerId = env("SMILE_ID_PARTNER_ID");
  const apiKey = env("SMILE_ID_API_KEY");
  if (!partnerId || !apiKey || !/^[0-9]{1,12}$/.test(partnerId)) return null;
  return { partnerId, apiKey, baseUrl: live ? SMILE_ID_LIVE : SMILE_ID_SANDBOX, fetch: f };
}

/// base64(HMAC-SHA256(api key, timestamp + partner id + "sid_request")).
export async function smileIdSignature(apiKey: string, timestamp: string, partnerId: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(apiKey), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(timestamp + partnerId + "sid_request")));
  let binary = "";
  for (const b of sig) binary += String.fromCharCode(b);
  return btoa(binary);
}

export function smileIdDocument(cfg: SmileIdConfig): IdDocumentProvider {
  return {
    name: "smile_id",
    startJob({ sessionId }) {
      // The session id names the job and the vendor-side user: nothing
      // that identifies the person in Attune leaves.
      return Promise.resolve({ ref: `attune_${sessionId}:${sessionId}` });
    },
    async result(ref): Promise<IdResult> {
      const [userId, jobId] = ref.split(":");
      if (!userId || !jobId) throw new Error("smile_id_bad_ref");
      const timestamp = (cfg.now ?? (() => new Date()))().toISOString();
      const body = {
        partner_id: cfg.partnerId,
        timestamp,
        signature: await smileIdSignature(cfg.apiKey, timestamp, cfg.partnerId),
        user_id: userId,
        job_id: jobId,
        image_links: false,
        history: false,
      };
      const res = await (cfg.fetch ?? fetch)(`${cfg.baseUrl}/v1/job_status`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(10000),
      });
      if (!res.ok) throw new Error(`smile_id_http_error_${res.status}`);
      return classifySmileIdJob(await res.json()); // Spec 2 W4 final (I-2): by ResultCode
    },
  };
}
