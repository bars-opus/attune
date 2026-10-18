// Spec 8 (row 8; plan review I15, §6.4): one content-free row per provider
// call, so cost per couple is known before the AI jobs resume. Written
// best-effort with the service role; a ledger failure never fails a call.
import { serviceRoleClient } from "./attune_auth.ts";

export type ProviderCallAttribution = {
  /** The edge function making the call, e.g. "analyse-message". */
  fn: string;
  relationshipId?: string | null;
  userId?: string | null;
};

export type ProviderCallRow = {
  fn: string;
  prompt_id: string;
  relationship_id: string | null;
  user_id: string | null;
  model: string | null;
  prompt_tokens: number;
  output_tokens: number;
};

type Recorder = (row: ProviderCallRow) => Promise<void>;

let recorder: Recorder | null = null;

/** Tests replace the writer; null restores the database one. */
export function setProviderCallRecorder(next: Recorder | null) {
  recorder = next;
}

async function insertRow(row: ProviderCallRow) {
  const { error } = await serviceRoleClient().from("ai_provider_calls").insert(row);
  if (error) throw error;
}

function tokens(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? Math.round(value)
    : 0;
}

export async function recordProviderCall(input: {
  attribution: ProviderCallAttribution;
  promptId: string;
  model: string | null;
  usage: unknown;
}): Promise<void> {
  const usage = (input.usage ?? {}) as Record<string, unknown>;
  const row: ProviderCallRow = {
    fn: input.attribution.fn.slice(0, 64),
    prompt_id: input.promptId.slice(0, 64),
    relationship_id: input.attribution.relationshipId ?? null,
    user_id: input.attribution.userId ?? null,
    model: input.model ? input.model.slice(0, 64) : null,
    prompt_tokens: tokens(usage.promptTokenCount),
    output_tokens: tokens(usage.candidatesTokenCount),
  };
  try {
    await (recorder ?? insertRow)(row);
  } catch {
    // Kind only, never the row (no ids in logs).
    console.error("provider_ledger_write_failed", { fn: row.fn });
  }
}
