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
  /** Spec 2 W3c: Child, Baby, Toddler or Infant (LABEL_DETECTION). */
  childLabelScore: number | null;
}

export interface ModerationConfig {
  minFaceConfidence: number;
  minFaceAreaRatio: number;
  childLabelReject?: number;
  childLabelReview?: number;
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
  // Spec 2 W3c (§3.2 D9): the five slot reasons. Unsafe first, then
  // children (a photo with a child can't be used), then the face.
  const flags = result.safeSearchFlags;
  if (REJECT_AT_POSSIBLE.has(flags.adult) || REJECT_AT_POSSIBLE.has(flags.violence) || REJECT_AT_LIKELY.has(flags.racy)) {
    return { state: "rejected", reason: "unsafe" };
  }
  const child = result.childLabelScore ?? 0;
  if (child >= (config.childLabelReject ?? 0.7)) return { state: "rejected", reason: "contains_child" };
  if (child >= (config.childLabelReview ?? 0.5)) return { state: "needs_review", reason: "needs_review" };
  if (!result.faceDetected || result.faceConfidence === null || result.faceConfidence < config.minFaceConfidence) {
    return { state: "needs_review", reason: "needs_review" };
  }
  if (result.faceBlurred || result.faceUnderexposed || result.faceAreaRatio === null || result.faceAreaRatio < config.minFaceAreaRatio) {
    return { state: "rejected", reason: "face_unclear" };
  }
  return { state: "approved", reason: null };
}

/** Spec 2 W3c: the highest score among the labels that mean a child. */
const CHILD_LABELS = new Set(["child", "baby", "toddler", "infant"]);
export function childScore(labels: unknown): number | null {
  if (!Array.isArray(labels)) return null;
  let best: number | null = null;
  for (const l of labels) {
    const name = typeof l?.description === "string" ? l.description.toLowerCase() : "";
    const score = typeof l?.score === "number" ? l.score : null;
    if (CHILD_LABELS.has(name) && score !== null && (best === null || score > best)) best = score;
  }
  return best;
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
            { type: "LABEL_DETECTION", maxResults: 50 }, // Spec 2 W3c fix round 1 (M-2): a Child label is not crowded out
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
    childLabelScore: childScore(annotation.labelAnnotations),
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
