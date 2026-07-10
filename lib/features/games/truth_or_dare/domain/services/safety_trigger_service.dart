// lib/features/games/truth_or_dare/domain/services/safety_trigger_service.dart

import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final safetyTriggerServiceProvider = Provider<SafetyTriggerService>((ref) {
  ref.read(supabaseClientProvider);
  return const SafetyTriggerService();
});

class SafetyTriggerService {
  const SafetyTriggerService();

  Future<bool> checkTruthAnswer({
    required String answer,
    required String userId,
    required String partnerId,
  }) async {
    return false;
  }
}
