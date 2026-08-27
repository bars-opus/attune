/// One question for any of the three session games (§8.4).
///
/// A single model rather than three: the games differ only in which
/// fields are populated, and game_questions is a single shared table
/// with a per-type CHECK. Three near-identical classes would drift.
class SessionGameQuestion {
  const SessionGameQuestion({
    required this.id,
    required this.gameType,
    required this.questionText,
    this.valueDomain,
    this.scaleLow,
    this.scaleHigh,
    this.options = const [],
  });

  final String id;
  final String gameType;
  final String questionText;

  /// Sliding Scale only: the §8.4 domain this statement belongs to.
  final String? valueDomain;

  /// Sliding Scale only: the 1 and 10 anchor labels.
  final String? scaleLow;
  final String? scaleHigh;

  /// Scenario only: its 3-4 response options. Empty for other types.
  final List<SessionGameOption> options;

  factory SessionGameQuestion.fromRow(Map<String, dynamic> row) {
    return SessionGameQuestion(
      id: row['id'] as String,
      gameType: row['game_type'] as String,
      questionText: row['question_text'] as String? ?? '',
      valueDomain: row['value_domain'] as String?,
      scaleLow: row['scale_low'] as String?,
      scaleHigh: row['scale_high'] as String?,
      options: _parseOptions(row['options']),
    );
  }

  /// Tolerant by design: `options` is a jsonb column, so a row written
  /// by a future migration could hold an unexpected shape. Returning an
  /// empty list degrades one question rather than throwing and taking
  /// down the whole list.
  static List<SessionGameOption> _parseOptions(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((entry) {
          final key = entry['key'];
          final text = entry['text'];
          if (key is! String || text is! String) return null;
          return SessionGameOption(key: key, text: text);
        })
        .whereType<SessionGameOption>()
        .toList();
  }
}

class SessionGameOption {
  const SessionGameOption({required this.key, required this.text});
  final String key;
  final String text;
}
