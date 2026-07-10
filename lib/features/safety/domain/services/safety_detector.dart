// lib/features/safety/domain/services/safety_detector.dart

class SafetyDetector {
  static const int tier1 = 1;
  static const int tier2 = 2;
  static const int tier3 = 3;

  /// Normalizes text for safety detection
  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[\u2018\u2019\u201A\u201B]'), "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Detect safety triggers in a message
  static SafetyDetectionResult detect(
    String message,
    Map<String, dynamic> config,
  ) {
    final normalized = normalize(message);
    if (normalized.isEmpty) {
      return SafetyDetectionResult.none();
    }

    final tokens = normalized.split(' ');
    final rules = _extractRules(config);
    final matches = <SafetyRuleMatch>[];

    for (final rule in rules) {
      final normalizedPattern = normalize(rule.pattern);
      if (normalizedPattern.isEmpty) {
        continue;
      }

      if (_phraseMatches(tokens, normalizedPattern.split(' '))) {
        matches.add(
          SafetyRuleMatch(
            ruleId: rule.id,
            tier: rule.tier,
            pattern: normalizedPattern,
          ),
        );
      }
    }

    if (matches.isEmpty) {
      return SafetyDetectionResult.none();
    }

    final tierGroups = <int, List<SafetyRuleMatch>>{};
    for (final match in matches) {
      tierGroups.putIfAbsent(match.tier, () => []).add(match);
    }

    final highestPriorityTier = tierGroups.keys.reduce((a, b) => a < b ? a : b);
    final tierMatches = tierGroups[highestPriorityTier]!;

    return SafetyDetectionResult(
      hasMatch: true,
      tier: highestPriorityTier,
      ruleIds: tierMatches.map((m) => m.ruleId).toList(),
      highestTier: highestPriorityTier,
      matchedPhrases: tierMatches.map((m) => m.pattern).toList(),
    );
  }

  static bool _phraseMatches(List<String> tokens, List<String> patternTokens) {
    if (patternTokens.length > tokens.length) return false;

    for (int i = 0; i <= tokens.length - patternTokens.length; i++) {
      bool match = true;
      for (int j = 0; j < patternTokens.length; j++) {
        if (tokens[i + j] != patternTokens[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  static List<SafetyRule> _extractRules(Map<String, dynamic> config) {
    final rules = <SafetyRule>[];
    final tiers = config['tiers'];
    if (tiers is! Map<String, dynamic>) {
      return rules;
    }

    for (final tierEntry in tiers.entries) {
      final tierData = tierEntry.value;
      if (tierData is! Map<String, dynamic>) {
        continue;
      }

      final tierNumber = tierData['tier'];
      final tierRules = tierData['rules'];
      if (tierNumber is! int || tierRules is! List<dynamic>) {
        continue;
      }

      for (final ruleData in tierRules) {
        if (ruleData is! Map<String, dynamic>) {
          continue;
        }

        final id = ruleData['id'];
        final pattern = ruleData['pattern'];
        if (id is! String || pattern is! String) {
          continue;
        }

        rules.add(
          SafetyRule(
            id: id,
            pattern: pattern,
            tier: tierNumber,
            minimumOccurrences: tierData['minimum_occurrences'] as int? ?? 1,
          ),
        );
      }
    }

    return rules;
  }
}

class SafetyRule {
  final String id;
  final String pattern;
  final int tier;
  final int minimumOccurrences;

  const SafetyRule({
    required this.id,
    required this.pattern,
    required this.tier,
    required this.minimumOccurrences,
  });
}

class SafetyRuleMatch {
  final String ruleId;
  final int tier;
  final String pattern;

  const SafetyRuleMatch({
    required this.ruleId,
    required this.tier,
    required this.pattern,
  });
}

class SafetyDetectionResult {
  final bool hasMatch;
  final int? tier;
  final List<String> ruleIds;
  final int? highestTier;
  final List<String> matchedPhrases;

  const SafetyDetectionResult({
    required this.hasMatch,
    this.tier,
    this.ruleIds = const [],
    this.highestTier,
    this.matchedPhrases = const [],
  });

  factory SafetyDetectionResult.none() {
    return const SafetyDetectionResult(hasMatch: false);
  }

  bool get isTier1 => tier == SafetyDetector.tier1;
  bool get isTier2 => tier == SafetyDetector.tier2;
  bool get isTier3 => tier == SafetyDetector.tier3;
}
