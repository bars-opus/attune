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

    final modeName = mode.remoteModeName;
    final relationshipStatus = _relationshipStatusForMode(mode);
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      await client
          .from('users')
          .upsert({
            'id': user.id,
            'phone': phone,
            'display_name': displayName,
            'mode': modeName,
          }, onConflict: 'id')
          .timeout(timeout);

      // The wider shipped app still reads from the legacy `profiles` surface
      // for profile/settings/opinions/forums. Mirror the minimum onboarding
      // identity there until the full migration to `users` is complete.
      await client
          .from('profiles')
          .upsert({
            'id': user.id,
            'display_name': displayName,
            'relationship_status': relationshipStatus,
            'updated_at': now,
          }, onConflict: 'id')
          .timeout(timeout);

      await client
          .from('onboarding_profiles')
          .upsert({
            'user_id': user.id,
            'mode': modeName,
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

  String _relationshipStatusForMode(OnboardingMode mode) {
    return mode == OnboardingMode.personal ? 'single' : 'taken';
  }
}
