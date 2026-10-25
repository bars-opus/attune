import 'dart:convert';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The sign-up draft on this phone, anonymous scope (Spec 1 §5.5):
/// `attune.flow.anonymous.signup_draft`. Kept until sign-up completes, for
/// 7 days, or until the under-18 stop deletes it (§4.8). Read
/// synchronously, so the router can resume a sign-up at launch. Only what
/// [SignUpDraft.keepable] allows is ever written or read back (review B5
/// fix round 5): no name or date of birth before a code was sent.
class SignUpDraftStore {
  SignUpDraftStore(this._prefs, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  static const key = 'attune.flow.anonymous.signup_draft';
  static const lifetime = Duration(days: 7);

  /// A draft dated further ahead than this was written under a clock that
  /// has since been set back; it is dropped too (review N-2).
  static const clockSkew = Duration(days: 1);

  /// The draft, or null when there is none, it is corrupt, it is older
  /// than 7 days, it is dated more than a day ahead, or nothing of it may
  /// be kept (then it is removed).
  SignUpDraft? read() => readFrom(_prefs, _now());

  static SignUpDraft? readFrom(SharedPreferences prefs, DateTime now) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    SignUpDraft? draft;
    try {
      draft = SignUpDraft.fromJson(jsonDecode(raw));
    } catch (_) {
      draft = null;
    }
    final kept = draft?.keepable;
    if (kept == null ||
        now.difference(kept.createdAt) > lifetime ||
        kept.createdAt.difference(now) > clockSkew) {
      prefs.remove(key);
      return null;
    }
    return kept;
  }

  /// Writes what may be kept of [draft]; with nothing, removes the key.
  Future<void> write(SignUpDraft draft) {
    final kept = draft.keepable;
    return kept == null
        ? _prefs.remove(key)
        : _prefs.setString(key, jsonEncode(kept.toJson()));
  }

  Future<void> clear() => _prefs.remove(key);
}

final signUpDraftStoreProvider = Provider<SignUpDraftStore>(
  (ref) => SignUpDraftStore(ref.watch(sharedPreferencesProvider)),
);
