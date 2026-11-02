// Logs carry codes and counts only (W4 batch 2 fix round 1): an error's
// own code, a Postgres SQLSTATE or a PostgREST PGRST code, when it looks
// like one, else "none". Never its message, details, hint or stack, which
// can hold a failing row (an invite code, a phone).
export function errorCode(error: unknown): string {
  const code = error && typeof error === "object" ? (error as { code?: unknown }).code : undefined;
  return typeof code === "string" && /^[A-Za-z0-9_]{1,24}$/.test(code) ? code : "none";
}
