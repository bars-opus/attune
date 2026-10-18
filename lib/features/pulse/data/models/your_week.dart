// lib/features/pulse/data/models/your_week.dart
import 'package:flutter/foundation.dart';

/// My own weekly check-in answers. Read only from my own weekly_checkins row
/// (auth.uid()-only RLS); never rendered to anyone else.
@immutable
class WeeklyCheckinAnswers {
  const WeeklyCheckinAnswers({
    required this.communication,
    required this.connection,
    required this.conflictHealth,
    required this.conflictHealthNA,
    required this.alignment,
    required this.safety,
  });

  factory WeeklyCheckinAnswers.fromJson(Map<String, dynamic> json) =>
      WeeklyCheckinAnswers(
        communication: (json['communication_rating'] as num?)?.toInt() ?? 0,
        connection: (json['connection_rating'] as num?)?.toInt() ?? 0,
        conflictHealth: (json['conflict_health_rating'] as num?)?.toInt(),
        conflictHealthNA: json['conflict_health_na'] == true,
        alignment: (json['alignment_rating'] as num?)?.toInt() ?? 0,
        safety: (json['safety_rating'] as num?)?.toInt() ?? 0,
      );

  final int communication;
  final int connection;
  final int? conflictHealth;
  final bool conflictHealthNA;
  final int alignment;
  final int safety;

  @override
  bool operator ==(Object other) =>
      other is WeeklyCheckinAnswers &&
      other.communication == communication &&
      other.connection == connection &&
      other.conflictHealth == conflictHealth &&
      other.conflictHealthNA == conflictHealthNA &&
      other.alignment == alignment &&
      other.safety == safety;

  @override
  int get hashCode => Object.hash(
    communication,
    connection,
    conflictHealth,
    conflictHealthNA,
    alignment,
    safety,
  );
}

/// The private "Your week" view: my check-in for the current week and my
/// latest private Emotional safety (pulse_private_scores).
@immutable
class YourWeek {
  const YourWeek({this.checkin, this.emotionalSafety, this.weekEnding});

  final WeeklyCheckinAnswers? checkin;
  final int? emotionalSafety;
  final DateTime? weekEnding;

  bool get hasCheckin => checkin != null;
}
