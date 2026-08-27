/// Mirror Game scoring (ATTUNE_MASTER_SPEC.md §8.4).
///
/// Pure and I/O-free so it is directly testable, and so the §11.1
/// visibility rules around the RESULT are enforced at the storage layer
/// (mirror_scores' RLS) rather than tangled into the arithmetic.

/// §8.4: "Score tracked: below 6.5/8 = attentiveness flag".
const double kAttentivenessFlagThreshold = 6.5;

/// Number of guesses the subject judged correct.
///
/// Correctness is a subjective judgement made by the SUBJECT — the
/// person whose inner state the round was about — not string equality.
/// "She's stressed about work" against "work has been overwhelming" is
/// a match, and no string comparison or fuzzy match would agree. This
/// function therefore takes the judgements, never the raw answers.
int mirrorScore(List<bool> judgements) =>
    judgements.where((correct) => correct).length;

/// Whether this score raises the §8.4 attentiveness flag.
///
/// Strictly below the threshold: 6/8 flags, 7/8 does not. The flag is
/// self-facing only (§11.1) — the caller must never surface it for the
/// partner.
bool isAttentivenessFlagged(int score, {int total = 8}) {
  if (total <= 0) return false;
  final scaled = score * (8 / total);
  return scaled < kAttentivenessFlagThreshold;
}
