// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'email_signup_attempt.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

EmailSignupAttempt _$EmailSignupAttemptFromJson(Map<String, dynamic> json) {
  return _EmailSignupAttempt.fromJson(json);
}

/// @nodoc
mixin _$EmailSignupAttempt {
  String? get id => throw _privateConstructorUsedError;
  String get emailHash => throw _privateConstructorUsedError;
  String? get originalEmailEncrypted => throw _privateConstructorUsedError;
  String? get userId => throw _privateConstructorUsedError;
  EmailVerificationStatus get verificationStatus =>
      throw _privateConstructorUsedError;
  EmailVerificationStatus? get previousVerificationStatus =>
      throw _privateConstructorUsedError;
  String get verificationSessionId => throw _privateConstructorUsedError;
  String? get deviceFingerprint => throw _privateConstructorUsedError;
  String? get userAgent => throw _privateConstructorUsedError;
  EmailVerificationAction? get lastVerificationAction =>
      throw _privateConstructorUsedError;
  int get verificationEmailCount => throw _privateConstructorUsedError;
  DateTime? get lastVerificationSentAt => throw _privateConstructorUsedError;
  int get totalVerificationAttempts => throw _privateConstructorUsedError;
  String? get verificationFailureReason => throw _privateConstructorUsedError;
  String? get ipHash => throw _privateConstructorUsedError;
  bool? get isSuspiciousVerification => throw _privateConstructorUsedError;
  DateTime? get verificationStartedAt => throw _privateConstructorUsedError;
  DateTime? get verificationUpdatedAt => throw _privateConstructorUsedError;
  DateTime? get verificationExpiresAt => throw _privateConstructorUsedError;
  DateTime? get emailVerifiedAt => throw _privateConstructorUsedError;

  /// Serializes this EmailSignupAttempt to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of EmailSignupAttempt
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $EmailSignupAttemptCopyWith<EmailSignupAttempt> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EmailSignupAttemptCopyWith<$Res> {
  factory $EmailSignupAttemptCopyWith(
          EmailSignupAttempt value, $Res Function(EmailSignupAttempt) then) =
      _$EmailSignupAttemptCopyWithImpl<$Res, EmailSignupAttempt>;
  @useResult
  $Res call(
      {String? id,
      String emailHash,
      String? originalEmailEncrypted,
      String? userId,
      EmailVerificationStatus verificationStatus,
      EmailVerificationStatus? previousVerificationStatus,
      String verificationSessionId,
      String? deviceFingerprint,
      String? userAgent,
      EmailVerificationAction? lastVerificationAction,
      int verificationEmailCount,
      DateTime? lastVerificationSentAt,
      int totalVerificationAttempts,
      String? verificationFailureReason,
      String? ipHash,
      bool? isSuspiciousVerification,
      DateTime? verificationStartedAt,
      DateTime? verificationUpdatedAt,
      DateTime? verificationExpiresAt,
      DateTime? emailVerifiedAt});
}

/// @nodoc
class _$EmailSignupAttemptCopyWithImpl<$Res, $Val extends EmailSignupAttempt>
    implements $EmailSignupAttemptCopyWith<$Res> {
  _$EmailSignupAttemptCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of EmailSignupAttempt
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? emailHash = null,
    Object? originalEmailEncrypted = freezed,
    Object? userId = freezed,
    Object? verificationStatus = null,
    Object? previousVerificationStatus = freezed,
    Object? verificationSessionId = null,
    Object? deviceFingerprint = freezed,
    Object? userAgent = freezed,
    Object? lastVerificationAction = freezed,
    Object? verificationEmailCount = null,
    Object? lastVerificationSentAt = freezed,
    Object? totalVerificationAttempts = null,
    Object? verificationFailureReason = freezed,
    Object? ipHash = freezed,
    Object? isSuspiciousVerification = freezed,
    Object? verificationStartedAt = freezed,
    Object? verificationUpdatedAt = freezed,
    Object? verificationExpiresAt = freezed,
    Object? emailVerifiedAt = freezed,
  }) {
    return _then(_value.copyWith(
      id: freezed == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String?,
      emailHash: null == emailHash
          ? _value.emailHash
          : emailHash // ignore: cast_nullable_to_non_nullable
              as String,
      originalEmailEncrypted: freezed == originalEmailEncrypted
          ? _value.originalEmailEncrypted
          : originalEmailEncrypted // ignore: cast_nullable_to_non_nullable
              as String?,
      userId: freezed == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String?,
      verificationStatus: null == verificationStatus
          ? _value.verificationStatus
          : verificationStatus // ignore: cast_nullable_to_non_nullable
              as EmailVerificationStatus,
      previousVerificationStatus: freezed == previousVerificationStatus
          ? _value.previousVerificationStatus
          : previousVerificationStatus // ignore: cast_nullable_to_non_nullable
              as EmailVerificationStatus?,
      verificationSessionId: null == verificationSessionId
          ? _value.verificationSessionId
          : verificationSessionId // ignore: cast_nullable_to_non_nullable
              as String,
      deviceFingerprint: freezed == deviceFingerprint
          ? _value.deviceFingerprint
          : deviceFingerprint // ignore: cast_nullable_to_non_nullable
              as String?,
      userAgent: freezed == userAgent
          ? _value.userAgent
          : userAgent // ignore: cast_nullable_to_non_nullable
              as String?,
      lastVerificationAction: freezed == lastVerificationAction
          ? _value.lastVerificationAction
          : lastVerificationAction // ignore: cast_nullable_to_non_nullable
              as EmailVerificationAction?,
      verificationEmailCount: null == verificationEmailCount
          ? _value.verificationEmailCount
          : verificationEmailCount // ignore: cast_nullable_to_non_nullable
              as int,
      lastVerificationSentAt: freezed == lastVerificationSentAt
          ? _value.lastVerificationSentAt
          : lastVerificationSentAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      totalVerificationAttempts: null == totalVerificationAttempts
          ? _value.totalVerificationAttempts
          : totalVerificationAttempts // ignore: cast_nullable_to_non_nullable
              as int,
      verificationFailureReason: freezed == verificationFailureReason
          ? _value.verificationFailureReason
          : verificationFailureReason // ignore: cast_nullable_to_non_nullable
              as String?,
      ipHash: freezed == ipHash
          ? _value.ipHash
          : ipHash // ignore: cast_nullable_to_non_nullable
              as String?,
      isSuspiciousVerification: freezed == isSuspiciousVerification
          ? _value.isSuspiciousVerification
          : isSuspiciousVerification // ignore: cast_nullable_to_non_nullable
              as bool?,
      verificationStartedAt: freezed == verificationStartedAt
          ? _value.verificationStartedAt
          : verificationStartedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      verificationUpdatedAt: freezed == verificationUpdatedAt
          ? _value.verificationUpdatedAt
          : verificationUpdatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      verificationExpiresAt: freezed == verificationExpiresAt
          ? _value.verificationExpiresAt
          : verificationExpiresAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      emailVerifiedAt: freezed == emailVerifiedAt
          ? _value.emailVerifiedAt
          : emailVerifiedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$EmailSignupAttemptImplCopyWith<$Res>
    implements $EmailSignupAttemptCopyWith<$Res> {
  factory _$$EmailSignupAttemptImplCopyWith(_$EmailSignupAttemptImpl value,
          $Res Function(_$EmailSignupAttemptImpl) then) =
      __$$EmailSignupAttemptImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String? id,
      String emailHash,
      String? originalEmailEncrypted,
      String? userId,
      EmailVerificationStatus verificationStatus,
      EmailVerificationStatus? previousVerificationStatus,
      String verificationSessionId,
      String? deviceFingerprint,
      String? userAgent,
      EmailVerificationAction? lastVerificationAction,
      int verificationEmailCount,
      DateTime? lastVerificationSentAt,
      int totalVerificationAttempts,
      String? verificationFailureReason,
      String? ipHash,
      bool? isSuspiciousVerification,
      DateTime? verificationStartedAt,
      DateTime? verificationUpdatedAt,
      DateTime? verificationExpiresAt,
      DateTime? emailVerifiedAt});
}

/// @nodoc
class __$$EmailSignupAttemptImplCopyWithImpl<$Res>
    extends _$EmailSignupAttemptCopyWithImpl<$Res, _$EmailSignupAttemptImpl>
    implements _$$EmailSignupAttemptImplCopyWith<$Res> {
  __$$EmailSignupAttemptImplCopyWithImpl(_$EmailSignupAttemptImpl _value,
      $Res Function(_$EmailSignupAttemptImpl) _then)
      : super(_value, _then);

  /// Create a copy of EmailSignupAttempt
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? emailHash = null,
    Object? originalEmailEncrypted = freezed,
    Object? userId = freezed,
    Object? verificationStatus = null,
    Object? previousVerificationStatus = freezed,
    Object? verificationSessionId = null,
    Object? deviceFingerprint = freezed,
    Object? userAgent = freezed,
    Object? lastVerificationAction = freezed,
    Object? verificationEmailCount = null,
    Object? lastVerificationSentAt = freezed,
    Object? totalVerificationAttempts = null,
    Object? verificationFailureReason = freezed,
    Object? ipHash = freezed,
    Object? isSuspiciousVerification = freezed,
    Object? verificationStartedAt = freezed,
    Object? verificationUpdatedAt = freezed,
    Object? verificationExpiresAt = freezed,
    Object? emailVerifiedAt = freezed,
  }) {
    return _then(_$EmailSignupAttemptImpl(
      id: freezed == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String?,
      emailHash: null == emailHash
          ? _value.emailHash
          : emailHash // ignore: cast_nullable_to_non_nullable
              as String,
      originalEmailEncrypted: freezed == originalEmailEncrypted
          ? _value.originalEmailEncrypted
          : originalEmailEncrypted // ignore: cast_nullable_to_non_nullable
              as String?,
      userId: freezed == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String?,
      verificationStatus: null == verificationStatus
          ? _value.verificationStatus
          : verificationStatus // ignore: cast_nullable_to_non_nullable
              as EmailVerificationStatus,
      previousVerificationStatus: freezed == previousVerificationStatus
          ? _value.previousVerificationStatus
          : previousVerificationStatus // ignore: cast_nullable_to_non_nullable
              as EmailVerificationStatus?,
      verificationSessionId: null == verificationSessionId
          ? _value.verificationSessionId
          : verificationSessionId // ignore: cast_nullable_to_non_nullable
              as String,
      deviceFingerprint: freezed == deviceFingerprint
          ? _value.deviceFingerprint
          : deviceFingerprint // ignore: cast_nullable_to_non_nullable
              as String?,
      userAgent: freezed == userAgent
          ? _value.userAgent
          : userAgent // ignore: cast_nullable_to_non_nullable
              as String?,
      lastVerificationAction: freezed == lastVerificationAction
          ? _value.lastVerificationAction
          : lastVerificationAction // ignore: cast_nullable_to_non_nullable
              as EmailVerificationAction?,
      verificationEmailCount: null == verificationEmailCount
          ? _value.verificationEmailCount
          : verificationEmailCount // ignore: cast_nullable_to_non_nullable
              as int,
      lastVerificationSentAt: freezed == lastVerificationSentAt
          ? _value.lastVerificationSentAt
          : lastVerificationSentAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      totalVerificationAttempts: null == totalVerificationAttempts
          ? _value.totalVerificationAttempts
          : totalVerificationAttempts // ignore: cast_nullable_to_non_nullable
              as int,
      verificationFailureReason: freezed == verificationFailureReason
          ? _value.verificationFailureReason
          : verificationFailureReason // ignore: cast_nullable_to_non_nullable
              as String?,
      ipHash: freezed == ipHash
          ? _value.ipHash
          : ipHash // ignore: cast_nullable_to_non_nullable
              as String?,
      isSuspiciousVerification: freezed == isSuspiciousVerification
          ? _value.isSuspiciousVerification
          : isSuspiciousVerification // ignore: cast_nullable_to_non_nullable
              as bool?,
      verificationStartedAt: freezed == verificationStartedAt
          ? _value.verificationStartedAt
          : verificationStartedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      verificationUpdatedAt: freezed == verificationUpdatedAt
          ? _value.verificationUpdatedAt
          : verificationUpdatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      verificationExpiresAt: freezed == verificationExpiresAt
          ? _value.verificationExpiresAt
          : verificationExpiresAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      emailVerifiedAt: freezed == emailVerifiedAt
          ? _value.emailVerifiedAt
          : emailVerifiedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$EmailSignupAttemptImpl implements _EmailSignupAttempt {
  const _$EmailSignupAttemptImpl(
      {this.id,
      required this.emailHash,
      this.originalEmailEncrypted,
      this.userId,
      required this.verificationStatus,
      this.previousVerificationStatus,
      required this.verificationSessionId,
      this.deviceFingerprint,
      this.userAgent,
      this.lastVerificationAction,
      this.verificationEmailCount = 1,
      this.lastVerificationSentAt,
      this.totalVerificationAttempts = 1,
      this.verificationFailureReason,
      this.ipHash,
      this.isSuspiciousVerification,
      this.verificationStartedAt,
      this.verificationUpdatedAt,
      this.verificationExpiresAt,
      this.emailVerifiedAt});

  factory _$EmailSignupAttemptImpl.fromJson(Map<String, dynamic> json) =>
      _$$EmailSignupAttemptImplFromJson(json);

  @override
  final String? id;
  @override
  final String emailHash;
  @override
  final String? originalEmailEncrypted;
  @override
  final String? userId;
  @override
  final EmailVerificationStatus verificationStatus;
  @override
  final EmailVerificationStatus? previousVerificationStatus;
  @override
  final String verificationSessionId;
  @override
  final String? deviceFingerprint;
  @override
  final String? userAgent;
  @override
  final EmailVerificationAction? lastVerificationAction;
  @override
  @JsonKey()
  final int verificationEmailCount;
  @override
  final DateTime? lastVerificationSentAt;
  @override
  @JsonKey()
  final int totalVerificationAttempts;
  @override
  final String? verificationFailureReason;
  @override
  final String? ipHash;
  @override
  final bool? isSuspiciousVerification;
  @override
  final DateTime? verificationStartedAt;
  @override
  final DateTime? verificationUpdatedAt;
  @override
  final DateTime? verificationExpiresAt;
  @override
  final DateTime? emailVerifiedAt;

  @override
  String toString() {
    return 'EmailSignupAttempt(id: $id, emailHash: $emailHash, originalEmailEncrypted: $originalEmailEncrypted, userId: $userId, verificationStatus: $verificationStatus, previousVerificationStatus: $previousVerificationStatus, verificationSessionId: $verificationSessionId, deviceFingerprint: $deviceFingerprint, userAgent: $userAgent, lastVerificationAction: $lastVerificationAction, verificationEmailCount: $verificationEmailCount, lastVerificationSentAt: $lastVerificationSentAt, totalVerificationAttempts: $totalVerificationAttempts, verificationFailureReason: $verificationFailureReason, ipHash: $ipHash, isSuspiciousVerification: $isSuspiciousVerification, verificationStartedAt: $verificationStartedAt, verificationUpdatedAt: $verificationUpdatedAt, verificationExpiresAt: $verificationExpiresAt, emailVerifiedAt: $emailVerifiedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EmailSignupAttemptImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.emailHash, emailHash) ||
                other.emailHash == emailHash) &&
            (identical(other.originalEmailEncrypted, originalEmailEncrypted) ||
                other.originalEmailEncrypted == originalEmailEncrypted) &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.verificationStatus, verificationStatus) ||
                other.verificationStatus == verificationStatus) &&
            (identical(other.previousVerificationStatus,
                    previousVerificationStatus) ||
                other.previousVerificationStatus ==
                    previousVerificationStatus) &&
            (identical(other.verificationSessionId, verificationSessionId) ||
                other.verificationSessionId == verificationSessionId) &&
            (identical(other.deviceFingerprint, deviceFingerprint) ||
                other.deviceFingerprint == deviceFingerprint) &&
            (identical(other.userAgent, userAgent) ||
                other.userAgent == userAgent) &&
            (identical(other.lastVerificationAction, lastVerificationAction) ||
                other.lastVerificationAction == lastVerificationAction) &&
            (identical(other.verificationEmailCount, verificationEmailCount) ||
                other.verificationEmailCount == verificationEmailCount) &&
            (identical(other.lastVerificationSentAt, lastVerificationSentAt) ||
                other.lastVerificationSentAt == lastVerificationSentAt) &&
            (identical(other.totalVerificationAttempts,
                    totalVerificationAttempts) ||
                other.totalVerificationAttempts == totalVerificationAttempts) &&
            (identical(other.verificationFailureReason,
                    verificationFailureReason) ||
                other.verificationFailureReason == verificationFailureReason) &&
            (identical(other.ipHash, ipHash) || other.ipHash == ipHash) &&
            (identical(
                    other.isSuspiciousVerification, isSuspiciousVerification) ||
                other.isSuspiciousVerification == isSuspiciousVerification) &&
            (identical(other.verificationStartedAt, verificationStartedAt) ||
                other.verificationStartedAt == verificationStartedAt) &&
            (identical(other.verificationUpdatedAt, verificationUpdatedAt) ||
                other.verificationUpdatedAt == verificationUpdatedAt) &&
            (identical(other.verificationExpiresAt, verificationExpiresAt) ||
                other.verificationExpiresAt == verificationExpiresAt) &&
            (identical(other.emailVerifiedAt, emailVerifiedAt) ||
                other.emailVerifiedAt == emailVerifiedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        emailHash,
        originalEmailEncrypted,
        userId,
        verificationStatus,
        previousVerificationStatus,
        verificationSessionId,
        deviceFingerprint,
        userAgent,
        lastVerificationAction,
        verificationEmailCount,
        lastVerificationSentAt,
        totalVerificationAttempts,
        verificationFailureReason,
        ipHash,
        isSuspiciousVerification,
        verificationStartedAt,
        verificationUpdatedAt,
        verificationExpiresAt,
        emailVerifiedAt
      ]);

  /// Create a copy of EmailSignupAttempt
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$EmailSignupAttemptImplCopyWith<_$EmailSignupAttemptImpl> get copyWith =>
      __$$EmailSignupAttemptImplCopyWithImpl<_$EmailSignupAttemptImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$EmailSignupAttemptImplToJson(
      this,
    );
  }
}

abstract class _EmailSignupAttempt implements EmailSignupAttempt {
  const factory _EmailSignupAttempt(
      {final String? id,
      required final String emailHash,
      final String? originalEmailEncrypted,
      final String? userId,
      required final EmailVerificationStatus verificationStatus,
      final EmailVerificationStatus? previousVerificationStatus,
      required final String verificationSessionId,
      final String? deviceFingerprint,
      final String? userAgent,
      final EmailVerificationAction? lastVerificationAction,
      final int verificationEmailCount,
      final DateTime? lastVerificationSentAt,
      final int totalVerificationAttempts,
      final String? verificationFailureReason,
      final String? ipHash,
      final bool? isSuspiciousVerification,
      final DateTime? verificationStartedAt,
      final DateTime? verificationUpdatedAt,
      final DateTime? verificationExpiresAt,
      final DateTime? emailVerifiedAt}) = _$EmailSignupAttemptImpl;

  factory _EmailSignupAttempt.fromJson(Map<String, dynamic> json) =
      _$EmailSignupAttemptImpl.fromJson;

  @override
  String? get id;
  @override
  String get emailHash;
  @override
  String? get originalEmailEncrypted;
  @override
  String? get userId;
  @override
  EmailVerificationStatus get verificationStatus;
  @override
  EmailVerificationStatus? get previousVerificationStatus;
  @override
  String get verificationSessionId;
  @override
  String? get deviceFingerprint;
  @override
  String? get userAgent;
  @override
  EmailVerificationAction? get lastVerificationAction;
  @override
  int get verificationEmailCount;
  @override
  DateTime? get lastVerificationSentAt;
  @override
  int get totalVerificationAttempts;
  @override
  String? get verificationFailureReason;
  @override
  String? get ipHash;
  @override
  bool? get isSuspiciousVerification;
  @override
  DateTime? get verificationStartedAt;
  @override
  DateTime? get verificationUpdatedAt;
  @override
  DateTime? get verificationExpiresAt;
  @override
  DateTime? get emailVerifiedAt;

  /// Create a copy of EmailSignupAttempt
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$EmailSignupAttemptImplCopyWith<_$EmailSignupAttemptImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
