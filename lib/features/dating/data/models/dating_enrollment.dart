import 'package:equatable/equatable.dart';

class DatingEnrollment extends Equatable {
  final String userId;
  final String state;
  final String? termsVersion;
  final DateTime? optedInAt;
  final DateTime? activatedAt;
  final DateTime? pausedAt;
  final DateTime? exitedAt;
  final DateTime? adultsOnlyConfirmedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DatingEnrollment({
    required this.userId,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.termsVersion,
    this.optedInAt,
    this.activatedAt,
    this.pausedAt,
    this.exitedAt,
    this.adultsOnlyConfirmedAt,
  });

  factory DatingEnrollment.fromJson(Map<String, dynamic> json) {
    DateTime? parseNullable(String key) {
      final raw = json[key];
      if (raw == null) {
        return null;
      }
      return DateTime.tryParse(raw as String);
    }

    return DatingEnrollment(
      userId: json['user_id'] as String,
      state: json['state'] as String? ?? 'ineligible',
      termsVersion: json['terms_version'] as String?,
      optedInAt: parseNullable('opted_in_at'),
      activatedAt: parseNullable('activated_at'),
      pausedAt: parseNullable('paused_at'),
      exitedAt: parseNullable('exited_at'),
      adultsOnlyConfirmedAt: parseNullable('adults_only_confirmed_at'),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  bool get isEligibleToOptIn => state == 'eligible_to_opt_in';
  bool get isProfileDraft => state == 'profile_draft';
  bool get isActive => state == 'active';
  bool get isPaused => state == 'paused';
  bool get isExited => state == 'exited';
  bool get isSuspended => state == 'suspended';

  @override
  List<Object?> get props => [
    userId,
    state,
    termsVersion,
    optedInAt,
    activatedAt,
    pausedAt,
    exitedAt,
    adultsOnlyConfirmedAt,
    createdAt,
    updatedAt,
  ];
}
