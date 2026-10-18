// Spec 8 (final review I-6): server-side reads of a feature flag. Any doubt
// is off: the flags read here switch on unreviewed (draft) content.

/// The private safety check's flag also switches on the rest of Spec 8's
/// draft safety content: the victimisation lexicon and the clinician-
/// pending cards.
export const DRAFT_SAFETY_CONTENT_FLAG = "private_safety_check";

// deno-lint-ignore no-explicit-any
export async function featureFlagEnabled(client: any, key: string): Promise<boolean> {
  try {
    const { data, error } = await client
      .from("feature_flags")
      .select("enabled")
      .eq("key", key)
      .maybeSingle();
    return !error && data?.enabled === true;
  } catch {
    return false;
  }
}
