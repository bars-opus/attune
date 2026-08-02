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
  faceBoundingPolyVertices: Array<{ x?: number; y?: number }> | null;
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

  // Image dimensions are not returned by Vision, so the precise area ratio
  // can't be computed here. The raw vertices are passed through so the
  // caller (which already has the decoded image's dimensions) can compute
  // it via computeFaceAreaRatio without a second Vision API call.
  const faceBoundingPolyVertices = primaryFace?.fdBoundingPoly?.vertices ?? null;

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
    faceAreaRatio: null,
    faceBoundingPolyVertices,
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
