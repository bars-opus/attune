// lib/features/quiz/domain/models/attachment_result.dart

class AttachmentResult {
  final int anxietyScore;
  final int avoidanceScore;
  final String resultType;
  final String displayName;
  final String poeticDescription;
  final List<String> practiceBullets;
  final int securePercentage;
  final int anxiousPercentage;
  final int avoidantPercentage;
  final int fearfulPercentage;

  AttachmentResult({
    required this.anxietyScore,
    required this.avoidanceScore,
    required this.resultType,
    required this.displayName,
    required this.poeticDescription,
    required this.practiceBullets,
    required this.securePercentage,
    required this.anxiousPercentage,
    required this.avoidantPercentage,
    required this.fearfulPercentage,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': resultType,
      'display_name': displayName,
      'anxiety_score': anxietyScore,
      'avoidance_score': avoidanceScore,
      'secure_pct': securePercentage,
      'anxious_pct': anxiousPercentage,
      'avoidant_pct': avoidantPercentage,
      'fearful_pct': fearfulPercentage,
      'completed_at': DateTime.now().toIso8601String(),
      'version': 1,
    };
  }

  @override
  String toString() {
    return 'AttachmentResult(type: $resultType, anxiety: $anxietyScore, avoidance: $avoidanceScore)';
  }
}
