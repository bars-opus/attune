// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_signup_attempt.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$EmailSignupAttemptImpl _$$EmailSignupAttemptImplFromJson(
        Map<String, dynamic> json) =>
    _$EmailSignupAttemptImpl(
      id: json['id'] as String?,
      emailHash: json['emailHash'] as String,
      originalEmailEncrypted: json['originalEmailEncrypted'] as String?,
      userId: json['userId'] as String?,
      verificationStatus: $enumDecode(
          _$EmailVerificationStatusEnumMap, json['verificationStatus']),
      previousVerificationStatus: $enumDecodeNullable(
          _$EmailVerificationStatusEnumMap, json['previousVerificationStatus']),
      verificationSessionId: json['verificationSessionId'] as String,
      deviceFingerprint: json['deviceFingerprint'] as String?,
      userAgent: json['userAgent'] as String?,
      lastVerificationAction: $enumDecodeNullable(
          _$EmailVerificationActionEnumMap, json['lastVerificationAction']),
      verificationEmailCount:
          (json['verificationEmailCount'] as num?)?.toInt() ?? 1,
      lastVerificationSentAt: json['lastVerificationSentAt'] == null
          ? null
          : DateTime.parse(json['lastVerificationSentAt'] as String),
      totalVerificationAttempts:
          (json['totalVerificationAttempts'] as num?)?.toInt() ?? 1,
      verificationFailureReason: json['verificationFailureReason'] as String?,
      ipHash: json['ipHash'] as String?,
      isSuspiciousVerification: json['isSuspiciousVerification'] as bool?,
      verificationStartedAt: json['verificationStartedAt'] == null
          ? null
          : DateTime.parse(json['verificationStartedAt'] as String),
      verificationUpdatedAt: json['verificationUpdatedAt'] == null
          ? null
          : DateTime.parse(json['verificationUpdatedAt'] as String),
      verificationExpiresAt: json['verificationExpiresAt'] == null
          ? null
          : DateTime.parse(json['verificationExpiresAt'] as String),
      emailVerifiedAt: json['emailVerifiedAt'] == null
          ? null
          : DateTime.parse(json['emailVerifiedAt'] as String),
    );

Map<String, dynamic> _$$EmailSignupAttemptImplToJson(
        _$EmailSignupAttemptImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'emailHash': instance.emailHash,
      'originalEmailEncrypted': instance.originalEmailEncrypted,
      'userId': instance.userId,
      'verificationStatus':
          _$EmailVerificationStatusEnumMap[instance.verificationStatus]!,
      'previousVerificationStatus':
          _$EmailVerificationStatusEnumMap[instance.previousVerificationStatus],
      'verificationSessionId': instance.verificationSessionId,
      'deviceFingerprint': instance.deviceFingerprint,
      'userAgent': instance.userAgent,
      'lastVerificationAction':
          _$EmailVerificationActionEnumMap[instance.lastVerificationAction],
      'verificationEmailCount': instance.verificationEmailCount,
      'lastVerificationSentAt':
          instance.lastVerificationSentAt?.toIso8601String(),
      'totalVerificationAttempts': instance.totalVerificationAttempts,
      'verificationFailureReason': instance.verificationFailureReason,
      'ipHash': instance.ipHash,
      'isSuspiciousVerification': instance.isSuspiciousVerification,
      'verificationStartedAt':
          instance.verificationStartedAt?.toIso8601String(),
      'verificationUpdatedAt':
          instance.verificationUpdatedAt?.toIso8601String(),
      'verificationExpiresAt':
          instance.verificationExpiresAt?.toIso8601String(),
      'emailVerifiedAt': instance.emailVerifiedAt?.toIso8601String(),
    };

const _$EmailVerificationStatusEnumMap = {
  EmailVerificationStatus.emailVerificationInitiated:
      'emailVerificationInitiated',
  EmailVerificationStatus.verificationEmailSent: 'verificationEmailSent',
  EmailVerificationStatus.emailVerified: 'emailVerified',
  EmailVerificationStatus.verificationAbandoned: 'verificationAbandoned',
  EmailVerificationStatus.verificationExpired: 'verificationExpired',
  EmailVerificationStatus.verificationFailed: 'verificationFailed',
};

const _$EmailVerificationActionEnumMap = {
  EmailVerificationAction.emailSignupInitiated: 'emailSignupInitiated',
  EmailVerificationAction.verificationEmailSent: 'verificationEmailSent',
  EmailVerificationAction.verificationEmailResent: 'verificationEmailResent',
  EmailVerificationAction.emailVerified: 'emailVerified',
  EmailVerificationAction.userCancelledVerification:
      'userCancelledVerification',
  EmailVerificationAction.emailChangedForVerification:
      'emailChangedForVerification',
  EmailVerificationAction.verificationNetworkError: 'verificationNetworkError',
  EmailVerificationAction.verificationTimeoutExpired:
      'verificationTimeoutExpired',
};
