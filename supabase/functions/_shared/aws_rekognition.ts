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
