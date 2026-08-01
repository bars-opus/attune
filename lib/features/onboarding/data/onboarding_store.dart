import 'dart:convert';

import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The payload of an onboarding submission that has not yet reached the server.
///
/// Onboarding completes locally even when the remote write fails (the user must
/// not be trapped in the flow by a bad network), so the submission is persisted
/// here and replayed on a later launch. Without this, "we will sync when your
/// connection is stable" is an empty promise and the user's mode / quiz answers
/// / anchors are silently lost server-side while they appear onboarded locally.
class PendingOnboardingSubmission {
  const PendingOnboardingSubmission({
    required this.mode,
    required this.displayName,
    required this.attachmentAnswers,
    required this.anchors,
  });

  final OnboardingMode mode;
  final String displayName;
  final List<int> attachmentAnswers;
  final List<String> anchors;

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'display_name': displayName,
    'attachment_answers': attachmentAnswers,
    'anchors': anchors,
  };

  static PendingOnboardingSubmission? fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String?;
    if (modeName == null) return null;
    OnboardingMode? mode;
    for (final value in OnboardingMode.values) {
      if (value.name == modeName) mode = value;
    }
    if (mode == null) return null;

    return PendingOnboardingSubmission(
      mode: mode,
      displayName: json['display_name'] as String? ?? '',
      attachmentAnswers:
          (json['attachment_answers'] as List?)?.whereType<int>().toList() ??
          const <int>[],
      anchors:
          (json['anchors'] as List?)?.whereType<String>().toList() ??
          const <String>[],
    );
  }
}

class OnboardingStore {
  const OnboardingStore(this._prefs, {required String scope}) : _scope = scope;

  final SharedPreferences _prefs;
  final String _scope;

  static const userScopePrefix = 'user';
  static const previewScope = 'preview';
  static const anonymousScope = 'anonymous';

  static const _completedKey = 'completed';
  static const _modeKey = 'mode';
  static const _displayNameKey = 'display_name';
  static const _pendingSubmissionKey = 'pending_submission';
  static const pendingInviteCodeKey = 'attune.onboarding.pending_invite_code';

  bool get isComplete => _prefs.getBool(_key(_completedKey)) ?? false;

  /// The submission still owed to the server, if the remote write failed.
  PendingOnboardingSubmission? get pendingSubmission {
    final raw = _prefs.getString(_key(_pendingSubmissionKey));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return PendingOnboardingSubmission.fromJson(decoded);
    } catch (_) {
      // Corrupt payload is unrecoverable; drop it rather than trap the retry.
      return null;
    }
  }

  Future<void> savePendingSubmission(PendingOnboardingSubmission submission) {
    return _prefs.setString(
      _key(_pendingSubmissionKey),
      jsonEncode(submission.toJson()),
    );
  }

  Future<void> clearPendingSubmission() {
    return _prefs.remove(_key(_pendingSubmissionKey));
  }

  OnboardingMode? get mode {
    final value = _prefs.getString(_key(_modeKey));
    if (value == null) return null;
    for (final mode in OnboardingMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }

  String? get displayName => _prefs.getString(_key(_displayNameKey));

  String? get pendingInviteCode => _prefs.getString(pendingInviteCodeKey);

  Future<void> storePendingInviteCode(String code) {
    return _prefs.setString(pendingInviteCodeKey, code);
  }

  Future<void> clearPendingInviteCode() {
    return _prefs.remove(pendingInviteCodeKey);
  }

  Future<void> complete({
    required OnboardingMode mode,
    required String displayName,
  }) async {
    await _prefs.setString(_key(_modeKey), mode.name);
    await _prefs.setString(_key(_displayNameKey), displayName);
    await _prefs.setBool(_key(_completedKey), true);
  }

  /// Moves an already-completed personal-mode user onto the couples track
  /// after they generate a partner invite from the Chat tab (see
  /// ChatCouplesLockedScreen) — NOT part of the one-time onboarding flow,
  /// which is the only other place `mode` was previously ever written.
  /// `completed` and `displayName` are untouched: this is a track change
  /// for an already-onboarded user, not a fresh completion.
  Future<void> startCouplesInvite() async {
    await _prefs.setString(_key(_modeKey), OnboardingMode.couplesPending.name);
  }

  Future<void> reset() async {
    await _prefs.remove(_key(_completedKey));
    await _prefs.remove(_key(_modeKey));
    await _prefs.remove(_key(_displayNameKey));
    await _prefs.remove(_key(_pendingSubmissionKey));
    await _prefs.remove(pendingInviteCodeKey);
  }

  String _key(String key) => 'attune.onboarding.$_scope.$key';
}
