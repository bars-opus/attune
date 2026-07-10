class ThisOrThatSession {
  final String id;
  final String relationshipId;
  final String initiatorId;
  final String tone;
  final String status;
  final int totalRounds;
  final int currentRound;
  final int matchCount;
  final int totalRoundsCompleted;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? abandonedAt;
  final DateTime createdAt;

  const ThisOrThatSession({
    required this.id,
    required this.relationshipId,
    required this.initiatorId,
    required this.tone,
    required this.status,
    required this.totalRounds,
    required this.currentRound,
    required this.matchCount,
    required this.totalRoundsCompleted,
    this.startedAt,
    this.completedAt,
    this.abandonedAt,
    required this.createdAt,
  });

  factory ThisOrThatSession.fromJson(Map<String, dynamic> json) {
    return ThisOrThatSession(
      id: json['id'],
      relationshipId: json['relationship_id'],
      initiatorId: json['initiator_id'],
      tone: json['tone'],
      status: json['status'],
      totalRounds: json['total_rounds'],
      currentRound: json['current_round'] ?? 0,
      matchCount: json['match_count'] ?? 0,
      totalRoundsCompleted: json['total_rounds_completed'] ?? 0,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'])
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
      abandonedAt: json['abandoned_at'] != null
          ? DateTime.parse(json['abandoned_at'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  double get matchPercentage =>
      totalRoundsCompleted > 0 ? (matchCount / totalRoundsCompleted) * 100 : 0;

  bool get showMatchBar => matchPercentage >= 60;
}
