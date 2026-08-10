// lib/features/moderation/presentation/providers/moderation_providers.dart

import 'package:attune/core/moderation/data/repositories/moderation_repository.dart';
import 'package:attune/features/auth/providers/auth_provider.dart'
    show authStateProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final moderationRepositoryProvider = Provider<ModerationRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return ModerationRepository(supabase);
});

// Current user ID — derives from authStateProvider (auth_provider.dart), NOT
// an imperative supabase.auth.currentUser read: a plain Provider<String?>
// reading currentUser once has no dependency that changes on sign-in, so it
// caches whatever it saw first (often null, from a signed-out screen)
// forever. See opinion_providers.dart's currentUserIdProvider for the full
// writeup of the bug this caused.
final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.id;
});

// Block a user
final blockUserProvider = FutureProvider.family<void, ({String blockedId, String? reason})>(
  (ref, params) async {
    final repository = ref.read(moderationRepositoryProvider);
    final currentUserId = ref.read(currentUserIdProvider);
    if (currentUserId == null) throw Exception('Not authenticated');
    await repository.blockUser(
      blockerId: currentUserId,
      blockedId: params.blockedId,
      reason: params.reason,
    );
  },
);

// Unblock a user
final unblockUserProvider = FutureProvider.family<void, String>((ref, blockedId) async {
  final repository = ref.read(moderationRepositoryProvider);
  final currentUserId = ref.read(currentUserIdProvider);
  if (currentUserId == null) throw Exception('Not authenticated');
  await repository.unblockUser(
    blockerId: currentUserId,
    blockedId: blockedId,
  );
  ref.invalidate(blockedUsersProvider);
});

// Get blocked users list
final blockedUsersProvider = FutureProvider<List<BlockedUser>>((ref) async {
  final repository = ref.read(moderationRepositoryProvider);
  final currentUserId = ref.read(currentUserIdProvider);
  if (currentUserId == null) return [];
  return await repository.getBlockedUsers(currentUserId);
});

// Check if current user has blocked a specific user
final hasBlockedProvider = FutureProvider.family<bool, String>((ref, targetUserId) async {
  final repository = ref.read(moderationRepositoryProvider);
  final currentUserId = ref.read(currentUserIdProvider);
  if (currentUserId == null) return false;
  return await repository.hasBlocked(currentUserId, targetUserId);
});

// Check if two users are mutually blocked (for chat entry)
final areMutuallyBlockedProvider = FutureProvider.family<bool, String>((ref, otherUserId) async {
  final repository = ref.read(moderationRepositoryProvider);
  final currentUserId = ref.read(currentUserIdProvider);
  if (currentUserId == null) return false;
  return await repository.areMutuallyBlocked(currentUserId, otherUserId);
});
