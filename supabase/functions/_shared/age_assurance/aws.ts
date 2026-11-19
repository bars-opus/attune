// supabase/functions/_shared/age_assurance/aws.ts
// Spec 2 W4a (§3.3.5): the real liveness and face-match providers, AWS
// Rekognition Face Liveness and CompareFaces, in the region the DPIA
// records (AWS_REKOGNITION_REGION; there is no default, and us-east-1 is
// refused: it is not used for UK or EU people). No S3 output is configured
// for liveness sessions and no audit images are kept (AuditImagesLimit 0):
// the reference frame comes back in the results call, is held in memory by
// the handler and cleared after the compare and the estimate.
import { compareFaces, rekognitionCall, RekognitionError } from "../aws_rekognition.ts";
import type { FaceMatchProvider, LivenessProvider, LivenessResult } from "./types.ts";

export interface AwsConfig {
  accessKeyId: string;
  secretAccessKey: string;
  region: string;
  fetch?: typeof fetch;
}

/// A config the real providers accept, or null (missing, or us-east-1).
export function awsConfigFrom(env: (name: string) => string | undefined, f?: typeof fetch): AwsConfig | null {
  const accessKeyId = env("AWS_REKOGNITION_ACCESS_KEY_ID");
  const secretAccessKey = env("AWS_REKOGNITION_SECRET_ACCESS_KEY");
  const region = env("AWS_REKOGNITION_REGION");
  if (!accessKeyId || !secretAccessKey || !region || !/^[a-z]{2}-[a-z]+-\d$/.test(region) || region === "us-east-1") {
    return null;
  }
  return { accessKeyId, secretAccessKey, region, fetch: f };
}

/// A pass needs the vendor's confidence at or above this (percent).
export const LIVENESS_MIN_CONFIDENCE = 90;

function decodeBase64(b64: string): Uint8Array {
  const binary = atob(b64);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

export function awsLiveness(cfg: AwsConfig): LivenessProvider {
  return {
    name: "aws_rekognition",
    async createSession() {
      const r = await rekognitionCall({ ...cfg, target: "CreateFaceLivenessSession", payload: { Settings: { AuditImagesLimit: 0 } } });
      const id = r.SessionId;
      if (typeof id !== "string" || id.length === 0 || id.length > 200) throw new Error("liveness_bad_session");
      return { ref: id };
    },
    async results(ref): Promise<LivenessResult> {
      const r = await rekognitionCall({ ...cfg, target: "GetFaceLivenessSessionResults", payload: { SessionId: ref } });
      switch (r.Status) {
        case "SUCCEEDED": {
          const bytes = (r.ReferenceImage as { Bytes?: unknown } | undefined)?.Bytes;
          const confidence = typeof r.Confidence === "number" ? r.Confidence : 0;
          if (confidence < LIVENESS_MIN_CONFIDENCE || typeof bytes !== "string") return { status: "failed", reference: null };
          return { status: "passed", reference: decodeBase64(bytes) };
        }
        case "FAILED":
          return { status: "failed", reference: null };
        case "EXPIRED":
          return { status: "expired", reference: null };
        case "CREATED":
        case "IN_PROGRESS":
          return { status: "pending", reference: null };
        default:
          throw new Error("liveness_unknown_status");
      }
    },
  };
}

const UNUSABLE_PHOTO: ReadonlySet<string> = new Set(["invalid_parameter", "invalid_image_format", "image_too_large"]);

export function awsFaceMatch(cfg: AwsConfig): FaceMatchProvider {
  return {
    name: "aws_rekognition",
    async compare(source, target) {
      // Only the boolean leaves compareFaces' answer; the similarity is
      // never read, logged or stored.
      try {
        return (await compareFaces({ sourceImageBytes: source, targetImageBytes: target, ...cfg })).matched;
      } catch (e) {
        // Task 2 fix round 1 (I-2 ruling): no face found, a format or a size
        // CompareFaces can't take is that photo not matching (the person can
        // change it: R-35), never "the vendor is down".
        if (e instanceof RekognitionError && UNUSABLE_PHOTO.has(e.kind)) return false;
        throw e;
      }
    },
  };
}
