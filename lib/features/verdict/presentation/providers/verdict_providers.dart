import 'package:attune/features/verdict/data/models/services/verdict_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final verdictServiceProvider = Provider<VerdictService>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return VerdictService(supabase);
});

final currentRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) {
    return null;
  }

  final response =
      await supabase
          .from('relationships')
          .select('id')
          .or('user_a.eq.$userId,user_b.eq.$userId')
          .eq('status', 'active')
          .maybeSingle();

  return response?['id'] as String?;
});

final verdictLoadProvider = FutureProvider<VerdictLoadState>((ref) async {
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) {
    final period = VerdictService.previousCompletedPeriodUtc();
    return VerdictLoadState(
      status: VerdictLoadStatus.unavailable,
      periodStart: period.start,
      periodEnd: period.end,
      message: 'No active relationship found.',
    );
  }

  final service = ref.read(verdictServiceProvider);
  return service.loadForRelationship(relationshipId);
});
