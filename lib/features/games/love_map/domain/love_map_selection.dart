/// Six months, per the spec: a question becomes eligible again this long
/// after it was answered, because what someone fears in July is not what
/// they feared in January. Re-asking is how the map keeps tracking an
/// evolving inner world instead of becoming a completed questionnaire.
const Duration kLoveMapReAskInterval = Duration(days: 182);

/// The coverage denominator — the seeded bank's size, asserted by
/// love_map_contracts.sql so the two cannot drift apart.
const int kLoveMapTotalQuestions = 60;

class LoveMapQuestion {
  const LoveMapQuestion({
    required this.id,
    required this.valueDomain,
    required this.text,
  });

  final String id;
  final String valueDomain;
  final String text;
}

/// Whether a question may be asked again.
bool isEligible({required DateTime? seenAt, required DateTime now}) {
  if (seenAt == null) return true;
  return now.difference(seenAt) >= kLoveMapReAskInterval;
}

/// Picks up to [count] questions, preferring domains the AI has detected in
/// chat.
///
/// Selection only. The model never writes question text, so no message
/// content can reach a question — a generated prompt could quote something
/// one partner said in confidence and put it in front of the other. With no
/// detected topics this degrades to plain rotation over the seeded bank,
/// which is also what makes Love Map work before any analysis exists.
List<LoveMapQuestion> selectQuestions({
  required List<LoveMapQuestion> pool,
  required List<String> detectedTopics,
  required int count,
}) {
  final preferred = <LoveMapQuestion>[];
  final rest = <LoveMapQuestion>[];
  for (final q in pool) {
    (detectedTopics.contains(q.valueDomain) ? preferred : rest).add(q);
  }
  return [...preferred, ...rest].take(count).toList();
}
