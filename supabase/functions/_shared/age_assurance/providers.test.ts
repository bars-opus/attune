// Spec 2 W4a (§3.3.5): the real providers' requests and answers, with an
// injected fetch (no network): AWS Face Liveness keeps no audit images and
// no S3 output, needs its confidence and is refused in us-east-1; Smile ID
// signs its job_status call, asks for no images and reads only the
// outcome, the face match and the date; the provider choice per mode.
import { awsConfigFrom, awsFaceMatch, awsLiveness, LIVENESS_MIN_CONFIDENCE } from "./aws.ts";
import { providersFor } from "./providers.ts";
import { classifySmileIdJob, SMILE_ID_SANDBOX, smileIdDocument, smileIdSignature } from "./smile_id.ts";

function eq(actual: unknown, expected: unknown, why = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${why} expected ${e}, got ${a}`);
}

const env = (vars: Record<string, string>) => (name: string) => vars[name];
const AWS = {
  AWS_REKOGNITION_ACCESS_KEY_ID: "AKIDEXAMPLE",
  AWS_REKOGNITION_SECRET_ACCESS_KEY: "secret",
  AWS_REKOGNITION_REGION: "eu-west-2",
};
const SMILE = { SMILE_ID_PARTNER_ID: "1234", SMILE_ID_API_KEY: "test-api-key" };

function recorder(answer: unknown, status = 200) {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const f = ((url: string, init: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(new Response(JSON.stringify(answer), { status }));
  }) as unknown as typeof fetch;
  return { calls, f };
}

Deno.test("AWS: no region, us-east-1 or a missing key runs nothing", () => {
  eq(awsConfigFrom(env({ ...AWS, AWS_REKOGNITION_REGION: "us-east-1" })), null);
  eq(awsConfigFrom(env({ ...AWS, AWS_REKOGNITION_REGION: "" })), null);
  eq(awsConfigFrom(env({ AWS_REKOGNITION_REGION: "eu-west-2" })), null);
  eq(awsConfigFrom(env(AWS))?.region, "eu-west-2");
});

Deno.test("AWS liveness: a session with no audit images and no S3 output", async () => {
  const r = recorder({ SessionId: "sess-1" });
  const p = awsLiveness({ ...awsConfigFrom(env(AWS))!, fetch: r.f });
  eq(await p.createSession({}), { ref: "sess-1" });
  const headers = r.calls[0].init.headers as Record<string, string>;
  eq([r.calls[0].url, headers["X-Amz-Target"]], ["https://rekognition.eu-west-2.amazonaws.com/", "RekognitionService.CreateFaceLivenessSession"]);
  eq(JSON.parse(String(r.calls[0].init.body)), { Settings: { AuditImagesLimit: 0 } });
});

Deno.test("AWS liveness: results by status and confidence; the frame decoded", async () => {
  const cases: Array<[unknown, string]> = [
    [{ Status: "SUCCEEDED", Confidence: LIVENESS_MIN_CONFIDENCE, ReferenceImage: { Bytes: btoa("JPEG") } }, "passed"],
    [{ Status: "SUCCEEDED", Confidence: LIVENESS_MIN_CONFIDENCE - 0.1, ReferenceImage: { Bytes: btoa("JPEG") } }, "failed"],
    [{ Status: "SUCCEEDED", Confidence: 99 }, "failed"],
    [{ Status: "FAILED" }, "failed"],
    [{ Status: "EXPIRED" }, "expired"],
    [{ Status: "IN_PROGRESS" }, "pending"],
  ];
  for (const [answer, want] of cases) {
    const r = recorder(answer);
    const res = await awsLiveness({ ...awsConfigFrom(env(AWS))!, fetch: r.f }).results("sess-1");
    eq(res.status, want, JSON.stringify(answer));
    if (want === "passed") eq(new TextDecoder().decode(res.reference!), "JPEG");
  }
  const bad = recorder({ Status: "SOMETHING_NEW" });
  let threw = false;
  try {
    await awsLiveness({ ...awsConfigFrom(env(AWS))!, fetch: bad.f }).results("sess-1");
  } catch {
    threw = true;
  }
  eq(threw, true, "an unknown status is an error, never a pass");
});

Deno.test("Smile ID: the signature and a job_status body asking for no images", async () => {
  eq(await smileIdSignature("test-api-key", "2026-11-09T10:00:00.000Z", "1234"), "Y/pgRyvB4c1kCAaMLc8beVj/dyY+TyQft30J1HHmiQA=");
  const r = recorder({ job_complete: false });
  const p = smileIdDocument({ partnerId: "1234", apiKey: "test-api-key", baseUrl: SMILE_ID_SANDBOX, fetch: r.f,
    now: () => new Date("2026-11-09T10:00:00.000Z") });
  const job = await p.startJob({ document: "ghana_card", country: "GH", sessionId: "s-1" });
  eq(job, { ref: "attune_s-1:s-1" });
  eq((await p.result(job.ref)).status, "pending");
  eq(r.calls[0].url, `${SMILE_ID_SANDBOX}/v1/job_status`);
  eq(JSON.parse(String(r.calls[0].init.body)), {
    partner_id: "1234", timestamp: "2026-11-09T10:00:00.000Z", signature: "Y/pgRyvB4c1kCAaMLc8beVj/dyY+TyQft30J1HHmiQA=",
    user_id: "attune_s-1", job_id: "s-1", image_links: false, history: false,
  });
});

// Spec 2 W4 final (I-2 ruling): a Smile ID job is classified by its
// ResultCode (Smile ID's documented Document Verification codes; sources
// in smile_id.ts). Only a document judged not genuine, or a confirmed
// document-face mismatch, is "fail" (final). Unreadable, expired,
// unsupported and image-quality answers are "retry" (never final; the
// handler waits for a person). An ID that shows under 18 is "minor"
// (Spec 1's hold, R-8). Anything not recognised, a code marked for the
// owner's sandbox check included, fails closed to "pending". Only 0810
// with the document passed and the face compare done is a pass. M-2: a
// date that isn't a calendar date is dropped (null), never sent on.
const done = (code: string, text: string, actions: Record<string, string> = {}, dob: unknown = "1990-05-05", success = true) =>
  ({ job_complete: true, job_success: success, result: { ResultCode: code, ResultText: text, Actions: actions, DOB: dob, FullName: "never read" } });
const VERIFIED = { Verify_Document: "Passed", Selfie_To_ID_Card_Compare: "Completed", Human_Review_Compare: "Not Applicable" };
const PASS = { status: "pass", dob: "1990-05-05", faceMatch: true };
const FAIL = { status: "fail", dob: null, faceMatch: null };
const RETRY = { status: "retry", dob: null, faceMatch: null };
const MINOR = { status: "minor", dob: null, faceMatch: null };
const PENDING = { status: "pending", dob: null, faceMatch: null };
const NOT_VERIFIED = "Unable to Verify Document - ";

Deno.test("W4 final I-2: Smile ID decision rows by ResultCode, one or more per class", async () => {
  const rows: Array<[string, unknown, unknown]> = [
    // Pass: 0810 only, with the document passed and the face compare done.
    ["0810 verified", done("0810", "Document Verified", VERIFIED), PASS],
    ["0810, a person's compare passed", done("0810", "Document Verified", { Verify_Document: "Passed", Human_Review_Compare: "Passed" }), PASS],
    ["0810, a date in another format", done("0810", "Document Verified", VERIFIED, "05/05/1990"), { status: "pass", dob: null, faceMatch: true }],
    ["0810, 30 February", done("0810", "Document Verified", VERIFIED, "1990-02-30"), { status: "pass", dob: null, faceMatch: true }],
    ["0810, job_success false", done("0810", "Document Verified", VERIFIED, "1990-05-05", false), PENDING],
    ["0810, the document not passed", done("0810", "Document Verified", { ...VERIFIED, Verify_Document: "Under Review" }), PENDING],
    ["0810, the compare under review", done("0810", "Document Verified", { ...VERIFIED, Selfie_To_ID_Card_Compare: "Under Review" }), PENDING],
    ["0810, no compare ran", done("0810", "Document Verified", { Verify_Document: "Passed" }), PENDING],
    ["0810, a person couldn't tell", done("0810", "Document Verified", { ...VERIFIED, Human_Review_Compare: "Unable to Determine" }), PENDING],
    ["0810, a person's compare failed", done("0810", "Document Verified", { ...VERIFIED, Human_Review_Compare: "Failed" }), PENDING],
    // Final: a confirmed document-face mismatch, or not genuine.
    ["0811 the selfie didn't match", done("0811", NOT_VERIFIED + "The selfie did not match the photo on document"), FAIL],
    ["0811 a person's compare failed", done("0811", NOT_VERIFIED + "something new", { Verify_Document: "Failed", Human_Review_Compare: "Failed" }), FAIL],
    ["0811 security features missing", done("0811", NOT_VERIFIED + "Some security features were missing on the document"), FAIL],
    ["0811 human review: potential fraud", done("0811", "Unable to Verify Document After Human Review (Potential Fraud Attempt)"), FAIL],
    // Under 18 on the document (R-8): Spec 1's hold.
    ["0811 under 18", done("0811", NOT_VERIFIED + "Based on the Date of Birth on the document, the subject is under 18 years old"), MINOR],
    // Retry: unreadable, unsupported, expired, image quality; never final.
    ["0811 selfie liveness failed", done("0811", NOT_VERIFIED + "Selfie failed liveness checks"), RETRY],
    ["0811 a wrong document type", done("0811", NOT_VERIFIED + "A wrong document type was uploaded"), RETRY],
    ["0811 human review: cropped", done("0811", "Unable to Verify Document After Human Review (Cropped Document)"), RETRY],
    ["0811 human review: not a document", done("0811", "Unable to Verify Document After Human Review (Not A Document)"), RETRY],
    ["0811 human review: unreadable", done("0811", "Unable to Verify Document After Human Review (Unreadable Document)"), RETRY],
    ["0811 human review: unsupported", done("0811", "Unable to Verify Document After Human Review (Unsupported Document)"), RETRY],
    ["0811 human review: wrong type", done("0811", "Unable to Verify Document After Human Review (Wrong Document Type)"), RETRY],
    ["0812 unclassifiable", done("0812", "Unable to verify Document - Document could not be classified", { Verify_Document: "Failed" }), RETRY],
    ["0816 unsupported document", done("0816", "Unable to verify Document - Unsupported Document"), RETRY],
    ["1014 unsupported ID type", done("1014", "Unsupported ID Type"), RETRY],
    ["0001 ID image unusable", done("0001", "Unable to Verify Document - ID Card image unusable"), RETRY],
    ["0001 selfie unusable", done("0001", "Unable to Verify Document - Selfie unusable"), RETRY],
    ["0001 images corrupt", done("0001", "Data Invalid - Images corrupt or not present"), RETRY],
    ["0001 system error", done("0001", "System Error"), RETRY],
    ["0903 zip corrupt", done("0903", "Zip Corrupt"), RETRY],
    ["0817 expired", done("0817", "Approved with Attention - Document is Expired", VERIFIED), RETRY],
    ["0817 photocopied", done("0817", "Approved with Attention - Photocopied Document", VERIFIED), RETRY],
    // Pending (a person checks): unsure, unknown, or not complete.
    ["0811 MRZ and OCR differ (owner sandbox check)", done("0811",
      NOT_VERIFIED + "The information on document is inconsistent i.e. the MRZ information did not match the OCR'ed information"), PENDING],
    ["0811 a reason never documented", done("0811", NOT_VERIFIED + "Something new", { Verify_Document: "Failed" }), PENDING],
    ["0817 suspicious device", done("0817", "Approved with Attention - Suspicious Device Detected", VERIFIED), PENDING],
    ["an undocumented code", done("0899", "Something new", { Verify_Document: "Failed", Selfie_To_ID_Card_Compare: "Failed" }), PENDING],
    ["no code at all, Verify_Document Failed", { job_complete: true, job_success: false, result: { Actions: { Verify_Document: "Failed" } } }, PENDING],
    ["not complete", { job_complete: false }, PENDING],
  ];
  // The ResultCode as a number (JSON may carry it either way) reads the same.
  const numeric = done("0810", "Document Verified", VERIFIED) as { result: Record<string, unknown> };
  numeric.result.ResultCode = 810;
  rows.push(["a numeric ResultCode is not guessed at", numeric, PENDING]);
  for (const [why, answer, want] of rows) {
    eq(classifySmileIdJob(answer), want, why);
    const r = recorder(answer);
    eq(await smileIdDocument({ partnerId: "1234", apiKey: "k", baseUrl: SMILE_ID_SANDBOX, fetch: r.f }).result("u:j"), want, `${why} (job_status)`);
  }
});

Deno.test("the providers per mode: sandbox and live need their keys; estimation stays unconfigured (R-9)", () => {
  eq(providersFor("sandbox", "development", env({})), null);
  eq(providersFor("live", "production", env(AWS)), null, "no Smile ID keys");
  const p = providersFor("live", "production", env({ ...AWS, ...SMILE }))!;
  eq([p.liveness.name, p.faceMatch.name, p.id.name, p.age.name], ["aws_rekognition", "aws_rekognition", "smile_id", "unconfigured"]);
});

Deno.test("fake runs only in development on the development project's or a local host (the Spec 1 W7b rule)", () => {
  const dev = ["http://127.0.0.1:54321", "http://kong:8000", "http://localhost:54321", "https://mrgjtyacrzfylawyzabm.supabase.co"];
  for (const url of dev) eq(providersFor("fake", "development", env({ SUPABASE_URL: url }))?.liveness.name, "fake", url);
  const not = ["", "not a url", "https://prodref.supabase.co", "https://mrgjtyacrzfylawyzabm.supabase.co.evil.example",
    "https://evil.example/?h=127.0.0.1"];
  for (const url of not) eq(providersFor("fake", "development", env({ SUPABASE_URL: url })), null, url);
  eq(providersFor("fake", "development", env({})), null, "no SUPABASE_URL");
  for (const environment of ["production", "staging", ""]) {
    eq(providersFor("fake", environment, env({ SUPABASE_URL: "http://127.0.0.1:54321" })), null, environment);
  }
});

// Task 2 fix round 1 (I-2 ruling): an AWS refusal by its type alone. No face,
// a bad image format or an image too large is that photo not matching (the
// person can change it); throttling and 5xx are retryable; any other
// refusal is not; AWS's message never travels on.
Deno.test("AWS errors by type: an unusable photo is a mismatch; throttling and 5xx retry; the rest is refused", async () => {
  const cfg = awsConfigFrom(env(AWS))!;
  const src = new TextEncoder().encode("SRC"), tgt = new TextEncoder().encode("TGT");
  const secret = "There are no faces in the image: secret-detail";
  for (const type of ["InvalidParameterException", "com.amazonaws.rekognition#InvalidImageFormatException", "ImageTooLargeException"]) {
    const r = recorder({ __type: type, message: secret }, 400);
    eq(await awsFaceMatch({ ...cfg, fetch: r.f }).compare(src, tgt, 0), false, type);
    eq(r.calls.length, 1, `${type}: one call`);
  }
  const cases: Array<[unknown, number, boolean]> = [
    [{ __type: "ThrottlingException", message: secret }, 400, true],
    [{ __type: "ProvisionedThroughputExceededException" }, 400, true],
    [{ __type: "InternalServerError" }, 500, true],
    [{}, 503, true],
    [{}, 429, true],
    [{ __type: "AccessDeniedException", message: secret }, 400, false],
    [{ __type: "constructor" }, 400, false],
    ["not json", 400, false],
  ];
  for (const [body, status, retryable] of cases) {
    const r = recorder(body, status);
    let err: { retryable?: unknown; message?: unknown } | null = null;
    try {
      await awsFaceMatch({ ...cfg, fetch: r.f }).compare(src, tgt, 0);
    } catch (e) {
      err = e as { retryable?: unknown; message?: unknown };
    }
    eq(err?.retryable, retryable, `${JSON.stringify(body)} ${status}`);
    eq(String(err?.message).includes("secret") || String(err?.message).includes("face"), false, "no AWS text");
  }
  // A liveness call's refusal is never a photo verdict.
  const live = recorder({ __type: "InvalidParameterException", message: secret }, 400);
  let threw: { retryable?: unknown } | null = null;
  try {
    await awsLiveness({ ...cfg, fetch: live.f }).results("sess-1");
  } catch (e) {
    threw = e as { retryable?: unknown };
  }
  eq(threw?.retryable, false, "liveness refusal");
  // A network failure is rethrown as it is (retryable by default).
  const down = (() => Promise.reject(new TypeError("network"))) as unknown as typeof fetch;
  let net: unknown = null;
  try {
    await awsFaceMatch({ ...cfg, fetch: down }).compare(src, tgt, 0);
  } catch (e) {
    net = e;
  }
  eq(net instanceof TypeError, true, "network error rethrown");
});

// Task 2 fix round 1 (M-6 ruling): sandbox results are not real verification;
// sandbox runs only in development, live anywhere.
Deno.test("sandbox runs only in development; live in production", () => {
  const keys = env({ ...AWS, ...SMILE, SUPABASE_URL: "https://mrgjtyacrzfylawyzabm.supabase.co" }); // W4 final (M-9): the dev host
  eq(providersFor("sandbox", "production", keys), null, "sandbox in production");
  eq(providersFor("sandbox", "", keys), null, "sandbox, environment unknown");
  eq(providersFor("sandbox", "development", keys)?.id.name, "smile_id", "sandbox in development");
  eq(providersFor("live", "production", keys)?.id.name, "smile_id", "live in production");
});

// Spec 2 W4 final (M-9): sandbox, like fake, needs the development
// project's (or a local) host as well as the environment reading
// development: a production project never flipped from development runs
// nothing in sandbox.
Deno.test("W4 final M-9: sandbox needs the development project's or a local host", () => {
  const keys = (url?: string) => env({ ...AWS, ...SMILE, ...(url === undefined ? {} : { SUPABASE_URL: url }) });
  for (const url of ["http://127.0.0.1:54321", "https://mrgjtyacrzfylawyzabm.supabase.co"]) {
    eq(providersFor("sandbox", "development", keys(url))?.id.name, "smile_id", url);
  }
  for (const url of [undefined, "", "https://prodref.supabase.co", "https://mrgjtyacrzfylawyzabm.supabase.co.evil.example"]) {
    eq(providersFor("sandbox", "development", keys(url)), null, String(url));
  }
  eq(providersFor("live", "production", keys("https://prodref.supabase.co"))?.id.name, "smile_id", "live is not host-bound");
});
