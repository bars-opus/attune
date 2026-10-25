import 'dart:async';

import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingSubmissionService {
  OnboardingSubmissionService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  static const timeout = Duration(seconds: 30);

  SupabaseClient? get _safeClient {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<void> submit({
    required OnboardingMode mode,
    required String displayName,
    required List<int> attachmentAnswers,
    required List<String> anchors,
  }) async {
    final client = _safeClient;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;

    final phone = user.phone;
    if (phone == null) return;

    final relationshipStatus = _relationshipStatusForMode(mode);
    final now = DateTime.now().toUtc().toIso8601String();
    final name = clampDisplayName(displayName);

    try {
      // Spec 1 W1a: the client may update only its name (users.phone is
      // copied from auth.users, users.mode is retired, and the row itself is
      // created by record_eula_acceptance, which the EULA gate runs first).
      await client
          .from('users')
          .update({'display_name': name})
          .eq('id', user.id)
          .timeout(timeout);

      // The wider shipped app still reads from the legacy `profiles` surface
      // for profile/settings/opinions/forums. Mirror the minimum onboarding
      // identity there until the full migration to `users` is complete.
      await client
          .from('profiles')
          .upsert({
            'id': user.id,
            'display_name': name,
            'relationship_status': relationshipStatus,
            'updated_at': now,
          }, onConflict: 'id')
          .timeout(timeout);

      await client
          .from('onboarding_profiles')
          .upsert({
            // Spec 1 W1b: onboarding_profiles.mode is dropped with this release.
            'user_id': user.id,
            'attachment_answers': attachmentAnswers,
            'anchors': anchors,
            'completed_at': now,
          }, onConflict: 'user_id')
          .timeout(timeout);
    } catch (error) {
      debugPrint('[onboarding] remote submit failed: ${error.runtimeType}');
      rethrow;
    }
  }

  /// The characters a display name never keeps (final review M-1, as
  /// corrected): U+200B, U+200E, U+200F, U+202A to U+202E (bidi embeddings
  /// and overrides), U+2060 to U+2064, U+2066 to U+2069 (bidi isolates) and
  /// U+FEFF. Left in, a partner sees a blank or a spoofed name. ZWNJ
  /// (U+200C) and ZWJ (U+200D) stay: Persian and Indic names and emoji
  /// sequences need them. The same set as the server's
  /// private.strip_name_controls.
  static final _invisibleNameChars = RegExp(
    '[\u200B\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]',
  );

  /// What is left of a name once spaces, ZWNJ and ZWJ are set aside; a name
  /// with nothing left has nothing visible (the server's
  /// private.name_is_blank).
  static final _blankNameChars = RegExp('[\\s\u200C\u200D]');

  /// users.display_name holds at most 40 characters (the CHECK
  /// users_display_name_length, counted in code points like Postgres'
  /// char_length). The legacy name step has no limit, so the name is clamped
  /// here rather than failing the write and replaying it forever. Whole code
  /// points only: an emoji is never split. The controls go first and
  /// whitespace runs collapse, as on the server, and a name with nothing
  /// visible left is empty.
  @visibleForTesting
  static String clampDisplayName(String value) {
    final cleaned = value
        .replaceAll(_invisibleNameChars, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.replaceAll(_blankNameChars, '').isEmpty) return '';
    final runes = cleaned.runes;
    if (runes.length <= 40) return cleaned;
    return String.fromCharCodes(runes.take(40)).trimRight();
  }

  String _relationshipStatusForMode(OnboardingMode mode) {
    return mode == OnboardingMode.personal ? 'single' : 'taken';
  }
}
