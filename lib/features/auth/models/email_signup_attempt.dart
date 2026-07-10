import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

part 'email_signup_attempt.freezed.dart';
part 'email_signup_attempt.g.dart';

// Email-specific verification statuses
enum EmailVerificationStatus {
  emailVerificationInitiated,
  verificationEmailSent,
  emailVerified,
  verificationAbandoned,
  verificationExpired,
  verificationFailed,
}

// Email-specific verification actions
enum EmailVerificationAction {
  emailSignupInitiated,
  verificationEmailSent,
  verificationEmailResent,
  emailVerified,
  userCancelledVerification,
  emailChangedForVerification,
  verificationNetworkError,
  verificationTimeoutExpired,
}

@freezed
class EmailSignupAttempt with _$EmailSignupAttempt {
  const factory EmailSignupAttempt({
    String? id,
    required String emailHash,
    String? originalEmailEncrypted,
    String? userId,
    required EmailVerificationStatus verificationStatus,
    EmailVerificationStatus? previousVerificationStatus,
    required String verificationSessionId,
    String? deviceFingerprint,
    String? userAgent,
    EmailVerificationAction? lastVerificationAction,
    @Default(1) int verificationEmailCount,
    DateTime? lastVerificationSentAt,
    @Default(1) int totalVerificationAttempts,
    String? verificationFailureReason,
    String? ipHash,
    bool? isSuspiciousVerification,
    DateTime? verificationStartedAt,
    DateTime? verificationUpdatedAt,
    DateTime? verificationExpiresAt,
    DateTime? emailVerifiedAt,
  }) = _EmailSignupAttempt;

  factory EmailSignupAttempt.fromJson(Map<String, dynamic> json) =>
      _$EmailSignupAttemptFromJson(json);
}

// Email-specific helper
class EmailVerificationSession {
  static String generateVerificationSessionId() {
    return 'email_verif_sess_${DateTime.now().millisecondsSinceEpoch}_${UniqueKey().toString().substring(2, 10)}';
  }

  static String hashEmailForVerification(String email) {
    // Note: In production, this should be done server-side via Edge Function
    // This client-side version is just for local reference
    return 'email_hash_${email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase()}';
  }

  static bool isVerificationExpired(DateTime? expiresAt) {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt);
  }
}
