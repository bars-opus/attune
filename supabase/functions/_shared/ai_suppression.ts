// Spec 8 (F15 (1); research RISK_SOLUTIONS :56; plan review I10-I13, M4):
// where the safety system has fired for a relationship (any tier, 180
// days) or either member's private safety check is positive, no AI job
// reads its chat. The predicate lives in SQL (relationship_ai_suppressed,
// service-role only); this is the one way jobs ask it.

type RpcClient = {
  rpc: (
    fn: string,
    args: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: unknown }>;
};

export type Suppression = "yes" | "no" | "unknown";

/// The full answer (final review I-1). A caller that would act
/// irreversibly on "yes" (set messages aside, cancel a job) treats
/// "unknown" as "not this run" rather than as "yes".
export async function relationshipAiSuppression(
  supabase: RpcClient,
  relationshipId: string,
): Promise<Suppression> {
  try {
    const { data, error } = await supabase.rpc("relationship_ai_suppressed", {
      p_relationship_id: relationshipId,
    });
    if (error) return "unknown";
    let value: unknown = data;
    // The pg test adapter returns the row rather than the scalar.
    if (value && typeof value === "object") {
      const row = Array.isArray(value) ? value[0] : value;
      value = row && typeof row === "object"
        ? Object.values(row as Record<string, unknown>)[0]
        : undefined;
    }
    if (value === true) return "yes";
    if (value === false) return "no";
    return "unknown";
  } catch {
    return "unknown";
  }
}

/// Fail closed: any doubt is a yes. For callers that merely skip a run.
export async function relationshipAiSuppressed(
  supabase: RpcClient,
  relationshipId: string,
): Promise<boolean> {
  return (await relationshipAiSuppression(supabase, relationshipId)) !== "no";
}
