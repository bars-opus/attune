// Spec 3a (05 D.4 (a)): which pattern types Healing Stage 2 may use. The
// snapshot taken at ending (healing_ending_snapshots) wins over live rows.
export function pickPatternEvidence(
  snapshot: unknown[] | null | undefined,
  live: unknown[],
): string[] {
  const source = snapshot == null ? live : snapshot;
  return source
    .filter((value): value is string => typeof value === "string")
    .slice(0, 6);
}
