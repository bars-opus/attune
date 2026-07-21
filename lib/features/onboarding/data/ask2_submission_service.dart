import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Writes the quiz + anchors gathered during Ask 2 (ATTUNE_MASTER_SPEC.md
/// decision 29). Deliberately separate from OnboardingSubmissionService,
/// which writes Ask-1 identity fields (users/profiles/mode) this flow must
/// never touch — Ask 1 already completed those when the couple linked.
class Ask2SubmissionService {
  Ask2SubmissionService({SupabaseClient? client}) : _client = client;

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
    required List<int> attachmentAnswers,
    required List<String> anchors,
  }) async {
    final client = _safeClient;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;

    final now = DateTime.now().toUtc().toIso8601String();

    try {
      await client
          .from('onboarding_profiles')
          .update({
            'attachment_answers': attachmentAnswers,
            'anchors': anchors,
            'ask2_completed_at': now,
          })
          .eq('user_id', user.id)
          .timeout(timeout);
    } catch (error) {
      debugPrint('[ask2] remote submit failed: ${error.runtimeType}');
      rethrow;
    }
  }
}
