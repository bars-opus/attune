// supabase/functions/_shared/push_targets.ts
//
// Chat review #18: which devices a push may go to -- the recipient's own
// registered OneSignal subscriptions (push_tokens, written only by
// register_push_subscription as auth.uid()).

// deno-lint-ignore no-explicit-any
type Client = { from: (table: string) => any };

/** OneSignal subscription ids are UUIDs; register_push_subscription enforces it. */
const SUBSCRIPTION_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function loadPushSubscriptions(supabase: Client, userId: string): Promise<string[]> {
  const { data, error } = await supabase
    .from("push_tokens")
    .select("token")
    .eq("user_id", userId)
    .eq("is_active", true);
  if (error) throw new Error(`push_targets_failed:${error.code ?? "unknown"}`);
  return ((data ?? []) as { token?: unknown }[])
    .map((r) => r.token)
    .filter((t): t is string => typeof t === "string" && SUBSCRIPTION_ID.test(t));
}

/** A device OneSignal no longer knows is not targeted again. Never throws. */
export async function deactivatePushSubscriptions(supabase: Client, tokens: string[]): Promise<void> {
  if (tokens.length === 0) return;
  const { error } = await supabase
    .from("push_tokens")
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .in("token", tokens);
  if (error) console.error("deactivate push subscriptions failed", error.code ?? "unknown");
}
