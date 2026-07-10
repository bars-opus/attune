// lib/features/quiz/domain/services/attachment_scoring_service.dart
import 'package:attune/features/quiz/data/attachment_questions.dart';
import 'package:attune/features/quiz/domain/models/attachment_result.dart';
import 'package:attune/features/quiz/domain/models/question_data.dart';

class AttachmentScoringService {
  /// Calculate attachment style from raw answers (1-7 scale)
  /// Returns AttachmentResult with dimension scores, type, and display percentages
  static AttachmentResult calculateScore(Map<int, int?> answers) {
    // Step 1: Extract raw answers (ensure all 25 questions answered)
    final List<QuestionData> allQuestions =
        AttachmentQuestions.getAllQuestions();
    final List<int> rawScores = [];

    for (int i = 0; i < allQuestions.length; i++) {
      final answer = answers[i];
      if (answer == null) {
        throw Exception('Missing answer for question $i');
      }
      rawScores.add(answer);
    }

    // Step 2: Apply reverse scoring
    final List<int> adjustedScores = [];
    for (int i = 0; i < allQuestions.length; i++) {
      final question = allQuestions[i];
      final rawScore = rawScores[i];

      if (question.isReverseScored) {
        // Reverse score: 8 - raw_score (1→7, 2→6, 3→5, 4→4, 5→3, 6→2, 7→1)
        adjustedScores.add(8 - rawScore);
      } else {
        adjustedScores.add(rawScore);
      }
    }

    // Step 3: Separate by dimension
    final List<int> anxietyScores = [];
    final List<int> avoidanceScores = [];

    for (int i = 0; i < allQuestions.length; i++) {
      final question = allQuestions[i];
      final score = adjustedScores[i];

      if (question.dimension == 'A') {
        anxietyScores.add(score);
      } else if (question.dimension == 'V') {
        avoidanceScores.add(score);
      }
    }

    // Step 4: Calculate raw dimension averages (1.0 - 7.0)
    final double anxietyRaw =
        anxietyScores.reduce((a, b) => a + b) / anxietyScores.length;
    final double avoidanceRaw =
        avoidanceScores.reduce((a, b) => a + b) / avoidanceScores.length;

    // Step 5: Normalize to 0-100
    final int anxietyScore = _normalizeTo100(anxietyRaw);
    final int avoidanceScore = _normalizeTo100(avoidanceRaw);

    // Step 6: Determine attachment type
    final String resultType = _determineType(anxietyScore, avoidanceScore);

    // Step 7: Calculate display percentages (secure, anxious, avoidant, fearful)
    final Map<String, int> displayPercentages = _calculatePercentages(
      anxietyScore,
      avoidanceScore,
    );

    // Step 8: Get poetic description and practice bullets
    final String poeticDescription = _getPoeticDescription(resultType);
    final List<String> practiceBullets = _getPracticeBullets(resultType);
    final String displayName = _getDisplayName(resultType);

    return AttachmentResult(
      anxietyScore: anxietyScore,
      avoidanceScore: avoidanceScore,
      resultType: resultType,
      displayName: displayName,
      poeticDescription: poeticDescription,
      practiceBullets: practiceBullets,
      securePercentage: displayPercentages['secure'] ?? 0,
      anxiousPercentage: displayPercentages['anxious'] ?? 0,
      avoidantPercentage: displayPercentages['avoidant'] ?? 0,
      fearfulPercentage: displayPercentages['fearful'] ?? 0,
    );
  }

  static int _normalizeTo100(double rawScore) {
    // rawScore is between 1.0 and 7.0
    // Convert to 0-100: ((raw - 1) / 6) * 100
    final normalized = ((rawScore - 1) / 6) * 100;
    return normalized.round();
  }

  static String _determineType(int anxiety, int avoidance) {
    final bool lowAnxiety = anxiety < 40;
    final bool midAnxiety = anxiety >= 40 && anxiety <= 60;
    final bool highAnxiety = anxiety > 60;

    final bool lowAvoidance = avoidance < 40;
    final bool midAvoidance = avoidance >= 40 && avoidance <= 60;
    final bool highAvoidance = avoidance > 60;

    // Pure quadrants
    if (lowAnxiety && lowAvoidance) return 'secure';
    if (highAnxiety && lowAvoidance) return 'anxious';
    if (lowAnxiety && highAvoidance) return 'avoidant';
    if (highAnxiety && highAvoidance) return 'fearful';

    // Mixed types
    if (midAnxiety && lowAvoidance) return 'anxious_secure';
    if (lowAnxiety && midAvoidance) return 'secure_avoidant';
    if (highAnxiety && midAvoidance) return 'anxious_avoidant';
    if (midAnxiety && highAvoidance) return 'avoidant_anxious';
    if (midAnxiety && midAvoidance) return 'fearful_secure';

    // Fallback (should not happen)
    return 'secure';
  }

  static Map<String, int> _calculatePercentages(int anxiety, int avoidance) {
    // Formula from spec Section 3 Step 6
    final int securePct = (((100 - anxiety) + (100 - avoidance)) / 4).round();
    final int anxiousPct = ((anxiety * (100 - avoidance)) / 5000).round();
    final int avoidantPct = ((avoidance * (100 - anxiety)) / 5000).round();
    final int fearfulPct = ((anxiety * avoidance) / 5000).round();

    // Normalize to ensure sum is exactly 100
    int sum = securePct + anxiousPct + avoidantPct + fearfulPct;
    if (sum != 100) {
      // Find the largest value and add the remainder
      final remainder = 100 - sum;
      final values = {
        'secure': securePct,
        'anxious': anxiousPct,
        'avoidant': avoidantPct,
        'fearful': fearfulPct,
      };
      final largestKey =
          values.entries.reduce((a, b) => a.value > b.value ? a : b).key;

      final adjusted = <String, int>{...values};
      adjusted[largestKey] = adjusted[largestKey]! + remainder;

      return adjusted;
    }

    return {
      'secure': securePct,
      'anxious': anxiousPct,
      'avoidant': avoidantPct,
      'fearful': fearfulPct,
    };
  }

  static String _getDisplayName(String type) {
    switch (type) {
      case 'secure':
        return 'Secure';
      case 'anxious':
        return 'Anxious';
      case 'avoidant':
        return 'Avoidant';
      case 'fearful':
        return 'Fearful-avoidant';
      case 'anxious_secure':
        return 'Anxious-secure';
      case 'secure_avoidant':
        return 'Secure-avoidant';
      case 'anxious_avoidant':
        return 'Anxious-avoidant';
      case 'avoidant_anxious':
        return 'Avoidant-anxious';
      case 'fearful_secure':
        return 'Cautiously secure';
      default:
        return 'Secure';
    }
  }

  static String getDisplayNameFromType(String type) => _getDisplayName(type);

  static String getPoeticDescriptionFromType(String type) =>
      _getPoeticDescription(type);

  static List<String> getPracticeBulletsFromType(String type) =>
      _getPracticeBullets(type);

  static String _getPoeticDescription(String type) {
    switch (type) {
      case 'secure':
        return 'You approach relationships from a place of groundedness. You can be close without losing yourself, and give space without fear. You trust that people who care about you will stay — and that trust makes you easy to love.';
      case 'anxious':
        return 'You feel everything deeply in relationships — the warmth, the connection, and the uncertainty. Your sensitivity is real and it makes you attentive and caring. In moments of distance, your mind can race toward the worst. That is your nervous system, not the truth of the situation.';
      case 'avoidant':
        return 'You value your independence and you have learned to rely on yourself. Closeness can feel complicated — not because you do not care, but because you care in ways that are hard to show. Your self-sufficiency is a strength, and so is learning when to let someone in.';
      case 'fearful':
        return 'You want closeness and find it frightening at the same time. This is one of the most human experiences there is — wanting connection while also protecting yourself from it. You are not broken. You are someone who has learned caution, and who can learn trust.';
      case 'anxious_secure':
        return 'You are mostly grounded in your relationships but you feel things more intensely than others in moments of uncertainty. Your warmth and attentiveness are genuine strengths. When stress rises, reassurance helps you return to your steady self.';
      case 'secure_avoidant':
        return 'You are mostly comfortable in relationships but you guard your independence carefully. You can connect deeply when you choose to and you need space to feel like yourself. Your self-awareness about what you need is one of your greatest relational assets.';
      case 'anxious_avoidant':
        return 'You experience both the pull toward connection and the discomfort of closeness. This creates a push-pull dynamic in your relationships that can be exhausting for you. Understanding this pattern is the first step toward something more settled.';
      case 'avoidant_anxious':
        return 'You tend to keep distance in relationships but when something threatens the bond you do care about, anxiety surfaces quickly. Your independence is real and so is your capacity for connection — they just need the right conditions to coexist.';
      case 'fearful_secure':
        return 'You sit in the middle of the attachment landscape — neither strongly secure nor strongly insecure. You can connect and you have some uncertainty about it. This balance means you are open to growth in either direction.';
      default:
        return '';
    }
  }

  static List<String> _getPracticeBullets(String type) {
    switch (type) {
      case 'secure':
        return [
          'You can ask for what you need without excessive worry about the response',
          'You give your partner space without reading it as rejection',
          'You repair conflict relatively well because you trust the relationship can survive disagreement',
        ];
      case 'anxious':
        return [
          'You may check in more than you intend to when things feel uncertain',
          'Small signals from your partner can carry a lot of weight for you emotionally',
          'Explicit reassurance helps you — asking for it directly is more effective than hoping it appears',
        ];
      case 'avoidant':
        return [
          'Deep conversations or emotional intensity can feel draining rather than connecting',
          'You may withdraw when a partner needs more closeness than feels comfortable',
          'The best relationships for you have clear space and do not require constant emotional availability',
        ];
      case 'fearful':
        return [
          'You may find yourself wanting closeness and then pulling away when it arrives',
          'Trust builds very slowly for you and that is valid — it needs to be earned over time',
          'Therapy or structured self-reflection tends to produce the most meaningful shifts for this style',
        ];
      case 'anxious_secure':
        return [
          'You are mostly settled but benefit from occasional check-ins where your partner explicitly affirms the connection',
          'You notice distance more quickly than your partner probably realises',
          'Your instinct to reach out in uncertainty is healthy — watch that it does not tip into over-reassurance-seeking',
        ];
      case 'secure_avoidant':
        return [
          'You thrive when relationships have clear boundaries around time and space',
          'You express care more through actions than words — make sure your partner knows how to read that',
          'You are more emotionally available than you seem — letting people see that occasionally goes a long way',
        ];
      case 'anxious_avoidant':
        return [
          'You may find yourself frustrated by wanting more while also feeling overwhelmed when you get it',
          'Naming this dynamic out loud to a partner can reduce a lot of confusion between you',
          'Self-compassion is more useful here than self-analysis — this pattern usually has deep roots',
        ];
      case 'avoidant_anxious':
        return [
          'You tend to be fine until something specific triggers concern — then anxiety comes quickly',
          'Understanding your specific triggers is more useful than addressing avoidance or anxiety in general',
          'Partners who respect your need for space while being consistent tend to work well for you',
        ];
      case 'fearful_secure':
        return [
          'You have flexibility in how you relate — use it',
          'You are not locked into one pattern which means you can move toward security with intentional practice',
          'Notice what conditions bring out your more secure versus less secure side',
        ];
      default:
        return [];
    }
  }
}
