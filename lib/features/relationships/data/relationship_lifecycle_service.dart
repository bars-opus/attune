// lib/features/relationships/data/relationship_lifecycle_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/relationship_lifecycle.dart';

/// Thrown when ending a relationship fails, mirroring
/// RelationshipInviteException's shape (relationship_invite_service.dart)
/// so error handling stays consistent across this feature area.
class RelationshipLifecycleException implements Exception {
  const RelationshipLifecycleException(this.message);
  final String message;

  @override
  String toString() => 'RelationshipLifecycleException: $message';
}

typedef LifecycleRpc =
    Future<dynamic> Function(String fn, [Map<String, dynamic>? params]);

/// Pause, resume, end and seal a shared space (Spec 3a; research 05 D.1).
/// Every transition is an RPC run as the caller; none notifies anyone.
class RelationshipLifecycleService {
  RelationshipLifecycleService({SupabaseClient? client, LifecycleRpc? rpc})
    : _client = client,
      _rpc = rpc;

  final SupabaseClient? _client;
  final LifecycleRpc? _rpc;
  static const _timeout = Duration(seconds: 30);

  Future<dynamic> _call(String fn, [Map<String, dynamic>? params]) {
    final rpc = _rpc;
    if (rpc != null) return rpc(fn, params);
    final client = _client ?? Supabase.instance.client;
    return client.rpc(fn, params: params).timeout(_timeout);
  }

  Future<void> _transition(String fn, String relationshipId) async {
    try {
      await _call(fn, {'p_relationship_id': relationshipId});
    } catch (error) {
      if (error is PostgrestException &&
          (error.message.contains('lifecycle:not_active') ||
              error.message.contains('lifecycle:not_paused') ||
              error.message.contains('lifecycle:not_ended'))) {
        throw const RelationshipLifecycleException(
          'This shared space has already changed. Reopen Chat to see the latest.',
        );
      }
      throw const RelationshipLifecycleException(
        "Couldn't do that. Please try again.",
      );
    }
  }

  /// Spec 3a (R3-15): the RPC directly, as the caller. The old edge
  /// function ran it with the service role, which has no auth.uid().
  Future<void> endRelationship({required String relationshipId}) =>
      _transition('end_relationship', relationshipId);

  Future<void> pause(String relationshipId) =>
      _transition('pause_relationship', relationshipId);

  Future<void> resume(String relationshipId) =>
      _transition('resume_relationship', relationshipId);

  Future<void> seal(String relationshipId) =>
      _transition('seal_my_side', relationshipId);

  Future<RelationshipLifecycle?> fetchLifecycle() async {
    final rows = await _call('get_my_relationship_lifecycle') as List<dynamic>?;
    if (rows == null || rows.isEmpty) return null;
    return RelationshipLifecycle.fromRow(
      Map<String, dynamic>.from(rows.first as Map),
    );
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
