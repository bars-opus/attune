// lib/features/relationships/data/relationship_lifecycle_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown when ending a relationship fails, mirroring
/// RelationshipInviteException's shape (relationship_invite_service.dart)
/// so error handling stays consistent across this feature area.
class RelationshipLifecycleException implements Exception {
  const RelationshipLifecycleException(this.message);
  final String message;

  @override
  String toString() => 'RelationshipLifecycleException: $message';
}

class RelationshipLifecycleService {
  RelationshipLifecycleService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  static const _timeout = Duration(seconds: 30);

  SupabaseClient get _safeClient => _client ?? Supabase.instance.client;

  Future<void> endRelationship({required String relationshipId}) async {
    try {
      final response = await _safeClient.functions
          .invoke(
            'end-relationship',
            body: {'relationship_id': relationshipId},
          )
          .timeout(_timeout);
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw RelationshipLifecycleException(data['error'].toString());
      }
    } catch (error) {
      debugPrint('[relationship-lifecycle] end failed: ${error.runtimeType}');
      if (error is RelationshipLifecycleException) rethrow;
      throw const RelationshipLifecycleException(
        'Could not end this relationship. Please try again.',
      );
    }
  }
}

/// The caller's current active (status = 'active') relationship id, or
/// null if none. Read on-demand inside EndRelationshipAction's onTap
/// closure (not at SettingsConfig build time) so the Settings entry can
/// gate itself without threading a new parameter through
/// getSettingsSections's existing signature/call sites.
final activeRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final row = await supabase
      .from('relationships')
      .select('id')
      .eq('status', 'active')
      .or('user_a.eq.$userId,user_b.eq.$userId')
      .maybeSingle();
  return row?['id'] as String?;
});
