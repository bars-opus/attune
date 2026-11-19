export interface CompareFacesResult {
  matched: boolean;
  similarity: number | null;
}

const SIMILARITY_THRESHOLD = 90; // percent; tune after real-world testing

/// Spec 2 W4a (Task 2 fix round 1, I-2): what an AWS refusal was, by its
/// __type alone (never its message, which can describe the image).
export type RekognitionErrorKind =
  | "invalid_parameter" // e.g. no face found in an image
  | "invalid_image_format"
  | "image_too_large"
  | "throttled"
  | "server"
  | "refused";

const REKOGNITION_ERROR_TYPES: ReadonlyMap<string, RekognitionErrorKind> = new Map([
  ["InvalidParameterException", "invalid_parameter"],
  ["InvalidImageFormatException", "invalid_image_format"],
  ["ImageTooLargeException", "image_too_large"],
  ["ThrottlingException", "throttled"],
  ["ProvisionedThroughputExceededException", "throttled"],
  ["LimitExceededException", "throttled"],
  ["InternalServerError", "server"],
]);

/// A non-2xx answer. Only throttling and server errors are worth another
/// try; its message is the kind and the status, nothing of AWS's text.
export class RekognitionError extends Error {
  readonly kind: RekognitionErrorKind;
  readonly retryable: boolean;
  constructor(kind: RekognitionErrorKind, status: number) {
    super(`rekognition_${kind}_${status}`);
    this.name = "RekognitionError";
    this.kind = kind;
    this.retryable = kind === "throttled" || kind === "server";
  }
}

async function rekognitionFailure(response: Response): Promise<RekognitionError> {
  if (response.status >= 500) return new RekognitionError("server", response.status);
  if (response.status === 429) return new RekognitionError("throttled", response.status);
  let type = "";
  try {
    const body = await response.json();
    if (typeof body?.__type === "string") type = body.__type.split("#").pop() ?? "";
  } catch {
    // no body: refused
  }
  return new RekognitionError(REKOGNITION_ERROR_TYPES.get(type) ?? "refused", response.status);
}

export async function compareFaces(params: {
  sourceImageBytes: Uint8Array;
  targetImageBytes: Uint8Array;
  accessKeyId: string;
  secretAccessKey: string;
  region: string;
  /// Spec 2 W4a: tests pass their own; production uses the global fetch.
  fetch?: typeof fetch;
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

  const response = await (params.fetch ?? fetch)(`https://${host}/`, {
    method: "POST",
    headers,
    body,
    signal: AbortSignal.timeout(10000),
  });

  if (!response.ok) {
    throw await rekognitionFailure(response); // Spec 2 W4a (Task 2 fix round 1, I-2)
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

/// Spec 2 W4a (§3.3.5): one signed Rekognition call (the Face Liveness
/// session calls), signed as compareFaces is. A non-2xx answer throws a
/// RekognitionError (its kind and status only); nothing is logged.
export async function rekognitionCall(params: {
  target: string;
  payload: unknown;
  accessKeyId: string;
  secretAccessKey: string;
  region: string;
  fetch?: typeof fetch;
  timeoutMs?: number;
}): Promise<Record<string, unknown>> {
  const body = JSON.stringify(params.payload);
  const host = `rekognition.${params.region}.amazonaws.com`;
  const headers = await signRequest({
    method: "POST",
    host,
    region: params.region,
    service: "rekognition",
    target: `RekognitionService.${params.target}`,
    body,
    accessKeyId: params.accessKeyId,
    secretAccessKey: params.secretAccessKey,
  });
  const response = await (params.fetch ?? fetch)(`https://${host}/`, {
    method: "POST",
    headers,
    body,
    signal: AbortSignal.timeout(params.timeoutMs ?? 10000),
  });
  if (!response.ok) {
    throw await rekognitionFailure(response);
  }
  return await response.json();
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
      key as BufferSource,
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
