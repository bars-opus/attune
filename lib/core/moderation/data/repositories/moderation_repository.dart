// lib/features/moderation/data/repositories/moderation_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class ModerationRepository {
  final SupabaseClient _supabase;

  ModerationRepository(this._supabase);

  // Block a user
  Future<void> blockUser({
    required String blockerId,
    required String blockedId,
    String? reason,
  }) async {
    if (blockerId == blockedId) {
      throw Exception('Cannot block yourself');
    }

    await _supabase.from('user_blocks').insert({
      'blocker_id': blockerId,
      'blocked_id': blockedId,
      'reason': reason,
    });
  }

  // Unblock a user
  Future<void> unblockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    await _supabase
        .from('user_blocks')
        .delete()
        .eq('blocker_id', blockerId)
        .eq('blocked_id', blockedId);
  }

  // Get list of users the current user has blocked
  Future<List<BlockedUser>> getBlockedUsers(String userId) async {
    final response = await _supabase
        .from('user_blocks')
        .select('blocked_id, reason, created_at')
        .eq('blocker_id', userId)
        .order('created_at', ascending: false);

    final List<BlockedUser> blockedUsers = [];
    for (final json in response) {
      final blockedId = json['blocked_id'] as String;
      
      // Get profile info for blocked user
      final profileRes = await _supabase
          .from('profiles')
          .select('display_name')
          .eq('id', blockedId)
          .maybeSingle();
      
      blockedUsers.add(BlockedUser(
        userId: blockedId,
        displayName: profileRes?['display_name'] as String? ?? 'User',
        reason: json['reason'] as String?,
        blockedAt: DateTime.parse(json['created_at']),
      ));
    }
    return blockedUsers;
  }

  // Check if user A has blocked user B (one-way)
  Future<bool> hasBlocked(String blockerId, String blockedId) async {
    final response = await _supabase
        .from('user_blocks')
        .select('id')
        .eq('blocker_id', blockerId)
        .eq('blocked_id', blockedId)
        .maybeSingle();
    return response != null;
  }

  // Check if two users have a mutual block (either direction)
  Future<bool> areMutuallyBlocked(String userId1, String userId2) async {
    final response = await _supabase.rpc(
      'are_users_blocked',
      params: {'user1_id': userId1, 'user2_id': userId2},
    );
    return response as bool? ?? false;
  }
}

// Model for blocked user display
class BlockedUser {
  final String userId;
  final String displayName;
  final String? reason;
  final DateTime blockedAt;

  BlockedUser({
    required this.userId,
    required this.displayName,
    this.reason,
    required this.blockedAt,
  });
}
