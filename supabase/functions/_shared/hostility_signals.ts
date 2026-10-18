// Spec 8 (F15 (1); RISK_SOLUTIONS :122; plan review I14): stonewalling and
// contempt (`stonewall_rate`, `severe_rate`) stay out of Pulse and the
// Verdict until clinical sign-off. One flag, seeded off; any doubt is off.
export const HOSTILITY_FLAG = "chat_hostility_signals_enabled";

// deno-lint-ignore no-explicit-any
export async function hostilitySignalsEnabled(supabase: any): Promise<boolean> {
  try {
    const { data, error } = await supabase
      .from("feature_flags")
      .select("enabled")
      .eq("key", HOSTILITY_FLAG)
      .maybeSingle();
    if (error || !data) return false;
    return data.enabled === true;
  } catch {
    return false;
  }
}

/// Pattern types (free text from Layer 2) that carry the same signals.
export const HOSTILITY_PATTERN_TYPES = /stonewall|contempt|character[_\s-]?attack/i;
