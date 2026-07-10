// lib/features/pulse/data/models/pulse_score.dart

class PulseScore {
  final String id;
  final String relationshipId;
  final DateTime weekEnding;
  final DateTime computedAt;
  final int overallScore;
  final int communication;
  final int connection;
  final int conflictHealth;
  final int alignment;
  final int emotionalSafety;
  final String dataConfidence;
  final Map<String, dynamic>? dimensionConfidence;
  final Map<String, dynamic>? deltaVsPrevious;

  PulseScore({
    required this.id,
    required this.relationshipId,
    required this.weekEnding,
    required this.computedAt,
    required this.overallScore,
    required this.communication,
    required this.connection,
    required this.conflictHealth,
    required this.alignment,
    required this.emotionalSafety,
    required this.dataConfidence,
    this.dimensionConfidence,
    this.deltaVsPrevious,
  });

  factory PulseScore.fromJson(Map<String, dynamic> json) {
    return PulseScore(
      id: json['id'],
      relationshipId: json['relationship_id'],
      weekEnding: DateTime.parse(json['week_ending']),
      computedAt: DateTime.parse(json['computed_at']),
      overallScore: json['overall_score'],
      communication: json['communication'],
      connection: json['connection'],
      conflictHealth: json['conflict_health'],
      alignment: json['alignment'],
      emotionalSafety: json['emotional_safety'],
      dataConfidence: json['data_confidence'],
      dimensionConfidence: json['dimension_confidence'],
      deltaVsPrevious: json['delta_vs_previous'],
    );
  }

  int? getDeltaForDimension(String dimension) {
    if (deltaVsPrevious == null) return null;
    return deltaVsPrevious![dimension] as int?;
  }

  String getConfidenceForDimension(String dimension) {
    if (dimensionConfidence == null) return 'low';
    return dimensionConfidence![dimension] as String? ?? 'low';
  }
}
